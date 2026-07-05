//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftData

struct Sidebar: View {

    @Bindable var viewModel: PlanViewModel

    @Environment(PlanStore.self) private var store
    @Environment(MCPServerManager.self) private var mcpServerManager
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

    @State private var selection: SidebarSelection? = .mode(.graph)
    @State private var isInspectorPresented: Bool = true

    var body: some View {
        NavigationSplitView {
            sidebarList
                .listStyle(.sidebar)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)
                .safeAreaInset(edge: .top, spacing: 0) { sidebarHeader }
                .safeAreaInset(edge: .bottom, spacing: 0) { mcpServerStatusFooter }
                .toolbar { sidebarToolbarContent }
        } detail: {
            detail
                .inspector(isPresented: $isInspectorPresented) {
                    TaskInspectorPanel(viewModel: viewModel)
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
                .toolbar { toolbarContent }
        }
        .searchable(text: $viewModel.searchText, isPresented: $viewModel.isSearchPresented, prompt: "Search tasks…")
        .onChange(of: selection) { _, newValue in apply(newValue) }
        .alert(
            viewModel.activeAlert?.title ?? "",
            isPresented: alertPresented,
            presenting: viewModel.activeAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Sidebar list

    private var sidebarList: some View {
        List(selection: $selection) {
            Section("Views") {
                NavigationLink(value: SidebarSelection.overview) {
                    Label("Overview", systemImage: "square.grid.2x2")
                }
                NavigationLink(value: SidebarSelection.mode(.graph)) {
                    Label("Graph View", systemImage: PlanViewMode.graph.systemImage)
                }
                NavigationLink(value: SidebarSelection.mode(.list)) {
                    Label("List View", systemImage: PlanViewMode.list.systemImage)
                }
                NavigationLink(value: SidebarSelection.mode(.board)) {
                    Label("Board View", systemImage: PlanViewMode.board.systemImage)
                }
            }

            Section("Focus") {
                focusRow(.backlog, title: "Blocked")
                focusRow(.readyToStart, title: "Ready")
                focusRow(.inProgress, title: "In Progress")
                focusRow(.done, title: "Done")
                focusRow(.closed, title: "Closed")
            }
        }
    }

    // MARK: - Plan picker (sidebar header)

    private var sidebarHeader: some View {
        VStack(spacing: 0) {
            planPicker
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
        }
    }

    private var planPicker: some View {
        Picker("Project", selection: planSelectionBinding) {
            ForEach(plans) { plan in
                Label(plan.title.isEmpty ? "Untitled Plan" : plan.title, systemImage: plan.icon)
                    .tag(plan.id as UUID?)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }

    private var planSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.plan?.id },
            set: { newID in
                guard let plan = plans.first(where: { $0.id == newID }) else { return }
                viewModel.plan = plan
                viewModel.clearSelection()
            }
        )
    }

    // MARK: - MCP server status (sidebar footer)

    private var mcpServerStatusFooter: some View {
        SettingsLink {
            HStack(spacing: 6) {
                Circle()
                    .fill(mcpStatusColor)
                    .frame(width: 7, height: 7)
                Text(mcpStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("MCP server — open Settings to configure")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var mcpStatusColor: Color {
        switch mcpServerManager.status {
        case .stopped: .secondary
        case .starting: .yellow
        case .running: .green
        case .failed: .red
        }
    }

    private var mcpStatusText: String {
        switch mcpServerManager.status {
        case .stopped: "MCP Server Off"
        case .starting: "MCP Server Starting…"
        case .running(let port): "MCP Server :\(port)"
        case .failed: "MCP Server Error"
        }
    }

    private func focusRow(_ state: TaskDisplayState, title: String) -> some View {
        NavigationLink(value: SidebarSelection.focus(state)) {
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(viewModel.count(of: state))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: state.systemImage).foregroundStyle(state.color)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Group {
            if viewModel.plan == nil {
                EmptyPlansState { _ = store.createPlan() }
            } else if viewModel.showOverview {
                OverviewPane(viewModel: viewModel)
            } else {
                switch viewModel.viewMode {
                case .graph: GraphCanvasView(viewModel: viewModel)
                case .list: PlanListView(viewModel: viewModel)
                case .board: PlanBoardView(viewModel: viewModel)
                }
            }
        }
        .navigationTitle(currentViewTitle)
    }

    /// The title of the view currently shown (the plan name lives in the sidebar picker instead).
    private var currentViewTitle: String {
        if viewModel.showOverview { return "Overview" }
        if viewModel.activeFilters.count == 1, let filter = viewModel.activeFilters.first {
            return filter.description
        }
        return viewModel.viewMode.title
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sidebarToolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                openWindow(id: ProjectManagerWindow.windowID)
            } label: {
                Label("Project Manager", systemImage: "folder.badge.gearshape")
            }
            .help("Manage projects and their details")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.viewMode = .graph
                _ = viewModel.createTask(at: CGPoint(x: 400, y: 300))
            } label: {
                Label("New Task", systemImage: "plus.rectangle")
            }
            .disabled(viewModel.plan == nil)

            Button {
                viewModel.autoLayout()
            } label: {
                Label("Auto Layout", systemImage: "wand.and.stars")
            }
            .disabled(viewModel.plan == nil || viewModel.viewMode != .graph || viewModel.showOverview)
        }

        ToolbarSpacer(.flexible)

        ToolbarItemGroup(placement: .primaryAction) {
            zoomControls
        }

        ToolbarSpacer(.flexible)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.trailing")
            }
        }
    }

    @ViewBuilder
    private var zoomControls: some View {
        if viewModel.viewMode == .graph && !viewModel.showOverview {
            Button { setZoom(viewModel.zoomScale - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(viewModel.zoomScale * 100))%")
                .font(.callout.monospacedDigit())
                .frame(width: 42)
            Button { setZoom(viewModel.zoomScale + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
        }
    }

    private func setZoom(_ value: CGFloat) {
        viewModel.zoomScale = min(max(value, GraphMetrics.minZoom), GraphMetrics.maxZoom)
    }

    // MARK: - Selection handling

    private func apply(_ selection: SidebarSelection?) {
        switch selection {
        case .overview:
            viewModel.openOverview()
        case .mode(let mode):
            viewModel.activeFilters = []
            viewModel.viewMode = mode
        case .focus(let state):
            // Closed tasks aren't drawn on the graph, so show them in the list instead.
            viewModel.focus(on: state)
        case nil:
            break
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeAlert != nil },
            set: { if !$0 { viewModel.activeAlert = nil } }
        )
    }
}

/// Empty-state shown when there are no plans (spec §15.1).
private struct EmptyPlansState: View {
    var createPlan: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Create your first Flowplan")
                .font(.title3.weight(.semibold))
            Text("Map your tasks, connect dependencies, and see what is ready to start.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: createPlan) {
                Label("New Plan", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
