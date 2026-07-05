//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftData

/// Lists all projects and edits their metadata: name, description, and associated repositories.
struct ProjectManagerView: View {

    @Environment(PlanStore.self) private var store
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

    @State private var selectedPlanID: UUID?
    @State private var renamingPlan: Plan?
    @State private var renameText: String = ""

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
        "lock", "desktopcomputer", "map", "car", "puzzlepiece", "ladybug"
    ]

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPlanID) {
                ForEach(plans) { plan in
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
                        Button(role: .destructive) {
                            deletePlan(plan)
                        } label: {
                            Label("Delete Project", systemImage: "trash")
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
                        TextField("https://github.com/owner/repo", text: repoBinding(plan, index))
                            .textFieldStyle(.roundedBorder)
                        if let url = validURL(plan.repositoryURLs[index]) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open in browser")
                        }
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
