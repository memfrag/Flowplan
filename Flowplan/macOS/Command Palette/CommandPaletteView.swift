//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftData

// MARK: - Overlay

/// Hosts the command palette above the whole window: a dimmed, click-to-dismiss backdrop with the
/// palette panel anchored near the top (Spotlight-style). Attach with `.overlay` at the window root.
struct CommandPaletteOverlay: View {

    @Bindable var viewModel: PlanViewModel

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isCommandPalettePresented {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.isCommandPalettePresented = false }

                CommandPaletteView(viewModel: viewModel)
                    .padding(.top, 110)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: viewModel.isCommandPalettePresented)
    }
}

// MARK: - Palette

/// The command palette (⌘K): type-to-filter across app actions, view switching, project switching,
/// and jump-to-task. Arrow keys move the selection, Return executes, Escape dismisses.
struct CommandPaletteView: View {

    @Bindable var viewModel: PlanViewModel

    @Environment(PlanStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let sections = visibleSections()
        let flatItems = sections.flatMap(\.items)

        VStack(spacing: 0) {
            searchField(flatItems: flatItems)

            Divider()

            if flatItems.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                resultsList(sections: sections, flatItems: flatItems)
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear {
            query = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
    }

    // MARK: - Search field

    private func searchField(flatItems: [PaletteItem]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .foregroundStyle(.secondary)
            TextField("Type a command or search tasks…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onSubmit { execute(at: selectedIndex, in: flatItems) }
                .onKeyPress(.upArrow) {
                    moveSelection(-1, count: flatItems.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(1, count: flatItems.count)
                    return .handled
                }
                .onKeyPress(.escape) {
                    viewModel.isCommandPalettePresented = false
                    return .handled
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    private func resultsList(sections: [PaletteSection], flatItems: [PaletteItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                        ForEach(section.items) { item in
                            let index = flatItems.firstIndex(where: { $0.id == item.id }) ?? 0
                            row(item, isSelected: index == selectedIndex)
                                .id(item.id)
                                .onHover { hovering in
                                    if hovering { selectedIndex = index }
                                }
                                .onTapGesture { execute(at: index, in: flatItems) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 360)
            .onChange(of: selectedIndex) {
                if flatItems.indices.contains(selectedIndex) {
                    proxy.scrollTo(flatItems[selectedIndex].id)
                }
            }
        }
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.iconColor ?? .secondary)
                .frame(width: 20)
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Selection & execution

    private func moveSelection(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func execute(at index: Int, in flatItems: [PaletteItem]) {
        guard flatItems.indices.contains(index) else { return }
        viewModel.isCommandPalettePresented = false
        flatItems[index].action()
    }

    // MARK: - Item construction

    private func visibleSections() -> [PaletteSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var sections: [PaletteSection] = []

        let actions = filtered(actionItems(), query: trimmed)
        if !actions.isEmpty {
            sections.append(PaletteSection(id: "actions", title: "Actions", items: actions))
        }

        let projects = filtered(projectItems(), query: trimmed)
        if !projects.isEmpty {
            sections.append(PaletteSection(id: "projects", title: "Projects", items: projects))
        }

        // Tasks only appear once the user starts typing — listing every task on open is noise.
        if !trimmed.isEmpty {
            let tasks = filtered(taskItems(), query: trimmed)
            if !tasks.isEmpty {
                sections.append(PaletteSection(id: "tasks", title: "Tasks", items: Array(tasks.prefix(12))))
            }
        }

        return sections
    }

    /// Filters and ranks items for a query. Empty query passes everything through in given order.
    private func filtered(_ items: [PaletteItem], query: String) -> [PaletteItem] {
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item in score(item, query: query).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Match score: title prefix > word prefix > title contains > keyword contains.
    private func score(_ item: PaletteItem, query: String) -> Int? {
        let q = query.lowercased()
        let title = item.title.lowercased()
        if title.hasPrefix(q) { return 100 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 80 }
        if title.contains(q) { return 60 }
        if item.keywords.lowercased().contains(q) { return 40 }
        return nil
    }

    private func actionItems() -> [PaletteItem] {
        var items: [PaletteItem] = []
        let hasPlan = viewModel.plan != nil

        if hasPlan {
            items.append(PaletteItem(
                id: "action.newTask", title: "New Task",
                subtitle: "⌘N", systemImage: "plus.rectangle", keywords: "create add"
            ) { _ = viewModel.createTaskAtViewportCenter() })
        }

        // Selected-task actions, when exactly one task is selected.
        if let task = viewModel.selectedTask {
            let state = viewModel.displayState(of: task)
            if state == .readyToStart {
                items.append(PaletteItem(
                    id: "action.start", title: "Start “\(task.title)”",
                    subtitle: "Space", systemImage: "play.circle.fill", iconColor: .blue,
                    keywords: "begin in progress"
                ) { viewModel.start(task) })
            }
            if state != .done {
                items.append(PaletteItem(
                    id: "action.markDone", title: "Mark “\(task.title)” Done",
                    subtitle: "⌘↩", systemImage: "checkmark.circle.fill", iconColor: .green,
                    keywords: "complete finish"
                ) { viewModel.markDone(task) })
            }
            items.append(PaletteItem(
                id: "action.deleteTask", title: "Delete “\(task.title)”",
                subtitle: "⌫", systemImage: "trash", iconColor: .red, keywords: "remove"
            ) { viewModel.deleteSelectedTaskOrDependency() })
        }

        items.append(contentsOf: [
            PaletteItem(id: "view.overview", title: "Overview",
                        subtitle: nil, systemImage: "square.grid.2x2", keywords: "dashboard stats"
            ) { viewModel.openOverview() },
            PaletteItem(id: "view.graph", title: "Graph View",
                        subtitle: "⌘1", systemImage: PlanViewMode.graph.systemImage, keywords: "canvas nodes"
            ) { viewModel.activeFilters = []; viewModel.viewMode = .graph },
            PaletteItem(id: "view.list", title: "List View",
                        subtitle: "⌘2", systemImage: PlanViewMode.list.systemImage, keywords: "table"
            ) { viewModel.activeFilters = []; viewModel.viewMode = .list },
            PaletteItem(id: "view.board", title: "Board View",
                        subtitle: "⌘3", systemImage: PlanViewMode.board.systemImage, keywords: "kanban columns"
            ) { viewModel.activeFilters = []; viewModel.viewMode = .board },
            PaletteItem(id: "view.timeline", title: "Timeline View",
                        subtitle: "⌘4", systemImage: PlanViewMode.timeline.systemImage, keywords: "due dates calendar schedule"
            ) { viewModel.activeFilters = []; viewModel.viewMode = .timeline }
        ])

        if hasPlan {
            for (state, title) in [
                (TaskDisplayState.backlog, "Focus: Blocked"),
                (.readyToStart, "Focus: Ready"),
                (.inProgress, "Focus: In Progress"),
                (.done, "Focus: Done"),
                (.closed, "Focus: Closed")
            ] {
                items.append(PaletteItem(
                    id: "focus.\(state.rawValue)", title: title,
                    subtitle: nil, systemImage: state.systemImage, iconColor: state.color,
                    keywords: "filter show"
                ) { viewModel.focus(on: state) })
            }

            items.append(PaletteItem(
                id: "action.autoLayout", title: "Auto Layout",
                subtitle: nil, systemImage: "wand.and.stars", keywords: "arrange tidy reflow"
            ) { viewModel.autoLayout() })

            items.append(PaletteItem(
                id: "action.criticalPath",
                title: viewModel.showCriticalPath ? "Hide Critical Path" : "Show Critical Path",
                subtitle: nil, systemImage: "bolt.horizontal", keywords: "cpm bottleneck slack longest analysis"
            ) {
                viewModel.viewMode = .graph
                viewModel.showCriticalPath.toggle()
            })

            items.append(PaletteItem(
                id: "action.resetZoom", title: "Reset Zoom",
                subtitle: "⌘0", systemImage: "1.magnifyingglass", keywords: "100%"
            ) { viewModel.zoomScale = 1 })

            items.append(PaletteItem(
                id: "action.search", title: "Search Tasks",
                subtitle: "⌘F", systemImage: "magnifyingglass", keywords: "find filter"
            ) { viewModel.isSearchPresented = true })

            if viewModel.closedTaskCount > 0 {
                items.append(PaletteItem(
                    id: "action.deleteClosed", title: "Delete Closed Tasks…",
                    subtitle: "\(viewModel.closedTaskCount)", systemImage: "trash",
                    iconColor: .red, keywords: "cleanup purge archive remove closed"
                ) { viewModel.requestDeleteClosedTasks() })
            }
        }

        items.append(PaletteItem(
            id: "window.projectManager", title: "Project Manager",
            subtitle: nil, systemImage: "folder.badge.gearshape", keywords: "projects metadata rename icon"
        ) { openWindow(id: ProjectManagerWindow.windowID) })

        items.append(PaletteItem(
            id: "window.settings", title: "Settings",
            subtitle: "⌘,", systemImage: "gearshape", keywords: "preferences mcp server"
        ) { openSettings() })

        return items
    }

    private func projectItems() -> [PaletteItem] {
        store.allPlans().map { plan in
            let isCurrent = viewModel.plan?.id == plan.id
            return PaletteItem(
                id: "project.\(plan.id.uuidString)",
                title: plan.title.isEmpty ? "Untitled Plan" : plan.title,
                subtitle: isCurrent ? "Current Project" : "Switch Project",
                systemImage: plan.icon,
                keywords: "project plan open switch"
            ) {
                guard !isCurrent else { return }
                viewModel.plan = plan
                viewModel.clearSelection()
            }
        }
    }

    private func taskItems() -> [PaletteItem] {
        guard let plan = viewModel.plan else { return [] }
        let graph = plan.graph
        return viewModel.tasks.map { task in
            let state = graph.displayState(of: task.id)
            return PaletteItem(
                id: "task.\(task.id.uuidString)",
                title: "#\(task.number) \(task.title)",
                subtitle: state.description,
                systemImage: state.systemImage,
                iconColor: state.color,
                keywords: task.tags.joined(separator: " ") + " " + (task.category ?? "")
            ) { viewModel.openTaskInGraph(task) }
        }
    }
}

// MARK: - Model

private struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    var iconColor: Color?
    let keywords: String
    let action: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String?,
        systemImage: String,
        iconColor: Color? = nil,
        keywords: String,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.keywords = keywords
        self.action = action
    }
}

private struct PaletteSection: Identifiable {
    let id: String
    let title: String
    let items: [PaletteItem]
}
