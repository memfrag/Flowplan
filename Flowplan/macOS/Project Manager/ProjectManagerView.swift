//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftData

/// Lists all projects and edits their metadata: name, description, and associated repositories.
struct ProjectManagerView: View {

    @Environment(PlanStore.self) private var store
    @Query(sort: Plan.displayOrder) private var plans: [Plan]

    @State private var selectedPlanID: UUID?
    @State private var renamingPlan: Plan?
    @State private var renameText: String = ""
    @State private var groupingPlan: Plan?
    @State private var newGroupText: String = ""

    /// The repository URL currently being imported (drives the per-row spinner), if any.
    @State private var importingRepo: String?
    @State private var importAlert: ImportAlert?

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// SF Symbols offered as project icons.
    private static let iconChoices = [
        "folder", "tray.full", "shippingbox", "cube", "square.grid.2x2",
        "star", "flag", "bolt", "flame", "sparkles",
        "hammer", "wrench.and.screwdriver", "gearshape", "cpu", "terminal",
        "paintbrush", "pencil.and.ruler", "camera", "photo", "music.note",
        "gamecontroller", "book", "doc.text", "chart.bar", "calendar",
        "cart", "briefcase", "building.2", "house", "globe",
        "network", "server.rack", "leaf", "heart", "lightbulb", "paperplane",
        "app", "app.gift", "tv", "airplane",
        "checklist", "target", "clock", "person.2", "envelope", "megaphone",
        "dollarsign.circle", "chart.line.uptrend.xyaxis", "graduationcap", "cross.case",
        "lock", "desktopcomputer", "map", "car", "puzzlepiece", "ladybug",
        "macwindow", "laptopcomputer", "printer", "scanner", "pc",
        "fork.knife", "carrot", "umbrella", "thermometer", "app.grid",
        "suitcase", "graph.2d", "graph.3d", "basketball", "tennisball",
        "microphone", "bubble", "waveform", "bookmark", "link",
        "dumbbell", "trophy", "die.face.5", "popcorn", "key",
        "flask", "hanger", "tshirt", "movieclapper", "ticket",
        "film", "sunglasses"
    ]

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID }
    }

    /// A named run of consecutive projects sharing a group, in display order.
    private struct PlanSection {
        let name: String
        let plans: [Plan]
    }

    /// `plans` is already sorted by group, so equal-group runs are contiguous and can be sliced
    /// without re-sorting — which keeps section order identical to the flat query order.
    private var groupedPlans: [PlanSection] {
        plans.reduce(into: [PlanSection]()) { sections, plan in
            if let last = sections.last, last.name == plan.group {
                sections[sections.count - 1] = PlanSection(name: last.name, plans: last.plans + [plan])
            } else {
                sections.append(PlanSection(name: plan.group, plans: [plan]))
            }
        }
    }

    private func planRows(in section: PlanSection) -> some View {
        ForEach(section.plans) { plan in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title.isEmpty ? "Untitled Plan" : plan.title)
                    Text("\(plan.tasks.count) task\(plan.tasks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: plan.icon)
            }
            .tag(plan.id)
            .contextMenu {
                Button {
                    renameText = plan.title
                    renamingPlan = plan
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                groupMenu(for: plan)
                Button(role: .destructive) {
                    deletePlan(plan)
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            }
        }
        .onMove { source, destination in move(in: section, from: source, to: destination) }
    }

    /// Reorders within a single group. `.onMove` offsets are relative to the section's own array, so
    /// the move is applied to that slice and the *whole* display order is then handed to the store —
    /// passing the raw offsets against `plans` would scramble the other groups.
    private func move(in section: PlanSection, from source: IndexSet, to destination: Int) {
        var reorderedSection = section.plans
        reorderedSection.move(fromOffsets: source, toOffset: destination)
        let reordered = groupedPlans.flatMap { $0.name == section.name ? reorderedSection : $0.plans }
        store.reorderPlans(reordered)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPlanID) {
                ForEach(groupedPlans, id: \.name) { section in
                    Section {
                        planRows(in: section)
                    } header: {
                        // The ungrouped section leads and stays unlabelled, so projects look the
                        // same as before until the user actually starts grouping things.
                        if !section.name.isEmpty {
                            Text(section.name)
                        }
                    }
                }
            }
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        let plan = store.createPlan()
                        selectedPlanID = plan.id
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let plan = selectedPlan {
                editor(for: plan)
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder",
                    description: Text("Select a project to edit its details.")
                )
            }
        }
        .onAppear { if selectedPlanID == nil { selectedPlanID = plans.first?.id } }
        .alert("Rename Project", isPresented: renamePresented) {
            TextField("Project name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renamingPlan = nil }
        }
        .alert("New Group", isPresented: newGroupPresented) {
            TextField("Group name", text: $newGroupText)
            Button("Move") { commitNewGroup() }
            Button("Cancel", role: .cancel) { groupingPlan = nil }
        } message: {
            Text("Projects sharing a group name are listed together.")
        }
    }

    /// "Move to Group" submenu: every existing group, plus ungrouped and a new-group escape hatch.
    @ViewBuilder
    private func groupMenu(for plan: Plan) -> some View {
        Menu {
            Button {
                store.setGroup("", for: plan)
            } label: {
                if plan.group.isEmpty { Label("Ungrouped", systemImage: "checkmark") } else { Text("Ungrouped") }
            }
            let groups = store.planGroups()
            if !groups.isEmpty {
                Divider()
                ForEach(groups, id: \.self) { group in
                    Button {
                        store.setGroup(group, for: plan)
                    } label: {
                        if plan.group == group { Label(group, systemImage: "checkmark") } else { Text(group) }
                    }
                }
            }
            Divider()
            Button("New Group…") {
                newGroupText = ""
                groupingPlan = plan
            }
        } label: {
            Label("Move to Group", systemImage: "folder")
        }
    }

    private var newGroupPresented: Binding<Bool> {
        Binding(
            get: { groupingPlan != nil },
            set: { if !$0 { groupingPlan = nil } }
        )
    }

    private func commitNewGroup() {
        guard let plan = groupingPlan else { return }
        store.setGroup(newGroupText, for: plan)
        groupingPlan = nil
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renamingPlan != nil },
            set: { if !$0 { renamingPlan = nil } }
        )
    }

    private func commitRename() {
        guard let plan = renamingPlan else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            plan.title = trimmed
            plan.touch()
            store.save()
        }
        renamingPlan = nil
    }

    // MARK: - Editor

    private func editor(for plan: Plan) -> some View {
        Form {
            Section("Project") {
                TextField("Name", text: titleBinding(plan))
            }

            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
                    ForEach(Self.iconChoices, id: \.self) { symbol in
                        Button {
                            plan.icon = symbol
                            plan.touch()
                            store.save()
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(plan.icon == symbol ? Color.accentColor.opacity(0.22) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(plan.icon == symbol ? Color.accentColor : Color.secondary.opacity(0.25))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Group") {
                // `.id` rebuilds the field (reseeding its draft) when a different project is
                // selected, so the editor never shows a stale group name.
                GroupField(plan: plan, existingGroups: store.planGroups()) {
                    store.setGroup($0, for: plan)
                }
                .id(plan.id)
                Text("Projects sharing a group name are listed together in the sidebar and here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Description") {
                TextEditor(text: summaryBinding(plan))
                    .frame(minHeight: 100)
                    .font(.body)
            }

            Section("Repositories") {
                if plan.repositoryURLs.isEmpty {
                    Text("No repositories associated yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.repositoryURLs.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.secondary)
                        TextField(
                            "Repository URL",
                            text: repoBinding(plan, index),
                            prompt: Text("https://github.com/owner/repo")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        if let url = validURL(plan.repositoryURLs[index]) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open in browser")
                        }
                        importButton(plan: plan, repoURL: plan.repositoryURLs[index])
                        Button(role: .destructive) {
                            removeRepo(plan, at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                Button {
                    plan.repositoryURLs.append("")
                    plan.touch()
                    store.save()
                } label: {
                    Label("Add Repository", systemImage: "plus")
                }
            }

            Section("Details") {
                LabeledContent("Tasks", value: "\(plan.tasks.count)")
                LabeledContent("Created", value: plan.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Updated", value: plan.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(plan.title.isEmpty ? "Untitled Plan" : plan.title)
        .alert(
            importAlert?.title ?? "",
            isPresented: Binding(get: { importAlert != nil }, set: { if !$0 { importAlert = nil } }),
            presenting: importAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - GitHub import

    /// An "Import Issues" control, shown only for rows that parse as a GitHub repository.
    @ViewBuilder
    private func importButton(plan: Plan, repoURL: String) -> some View {
        if GitHubClient.parseRepo(from: repoURL) != nil {
            if importingRepo == repoURL {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    runImport(plan: plan, repoURL: repoURL)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Import issues from this repository")
                .disabled(importingRepo != nil)
            }
        }
    }

    private func runImport(plan: Plan, repoURL: String) {
        importingRepo = repoURL
        let service = GitHubImportService(planStore: store)
        Task {
            defer { importingRepo = nil }
            do {
                let summary = try await service.importIssues(from: repoURL, into: plan)
                importAlert = ImportAlert(title: "Import Complete", message: summary.message)
            } catch {
                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func validURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    private func deletePlan(_ plan: Plan) {
        let wasSelected = selectedPlanID == plan.id
        store.deletePlan(plan)
        if wasSelected {
            selectedPlanID = plans.first { $0.id != plan.id }?.id
        }
    }

    private func removeRepo(_ plan: Plan, at index: Int) {
        guard index < plan.repositoryURLs.count else { return }
        plan.repositoryURLs.remove(at: index)
        plan.touch()
        store.save()
    }

    private func titleBinding(_ plan: Plan) -> Binding<String> {
        Binding(
            get: { plan.title },
            set: { plan.title = $0; plan.touch(); store.save() }
        )
    }

    private func summaryBinding(_ plan: Plan) -> Binding<String> {
        Binding(
            get: { plan.summary },
            set: { plan.summary = $0; plan.touch(); store.save() }
        )
    }

    private func repoBinding(_ plan: Plan, _ index: Int) -> Binding<String> {
        Binding(
            get: { index < plan.repositoryURLs.count ? plan.repositoryURLs[index] : "" },
            set: {
                guard index < plan.repositoryURLs.count else { return }
                plan.repositoryURLs[index] = $0
                plan.touch()
                store.save()
            }
        )
    }
}

/// The group-name field in the project editor: a combo box that completes against the groups already
/// in use, while still accepting a brand new name.
///
/// Edits are held in a local draft and only committed once the value settles (picked from the list,
/// or editing finished). Committing on every keystroke would re-sort the project list — and reassign
/// the project's sort order — after each character typed.
private struct GroupField: View {

    let plan: Plan
    let existingGroups: [String]
    let commit: (String) -> Void

    @State private var draft: String

    init(plan: Plan, existingGroups: [String], commit: @escaping (String) -> Void) {
        self.plan = plan
        self.existingGroups = existingGroups
        self.commit = commit
        _draft = State(initialValue: plan.group)
    }

    var body: some View {
        ComboBoxField(
            text: $draft,
            placeholder: "Ungrouped",
            completions: existingGroups,
            onCommit: commit
        )
        .frame(height: 22)
    }
}
