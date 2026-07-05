//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox

/// The right-hand inspector for the selected task (spec §7.5). Built from SwiftUIToolbox's
/// inspector grid components, with custom dependency sections below.
struct TaskInspectorPanel: View {

    @Bindable var viewModel: PlanViewModel

    var body: some View {
        if let task = viewModel.selectedTask {
            ScrollView {
                content(for: task)
                    .padding(.vertical, 8)
            }
        } else if viewModel.selectedTaskIDs.count > 1 {
            multiSelection
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "sidebar.right",
                description: Text("Select a task to see its details and dependencies.")
            )
        }
    }

    /// Shown when several tasks are selected at once (shift-drag / shift-click). Detailed editing is
    /// single-task; bulk state changes and deletion live in the canvas context menu and Task menu.
    private var multiSelection: some View {
        ContentUnavailableView {
            Label("\(viewModel.selectedTaskIDs.count) Tasks Selected", systemImage: "square.stack.3d.up")
        } description: {
            Text("Right-click a selected task to change status or delete them together, or drag to move them all at once.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)

        VStack(alignment: .leading, spacing: 16) {
            InspectorGrid {
                InspectorSectionHeader("Task")

                GridRow {
                    InspectorLabel("ID")
                    InspectorTextValue("\(task.number)")
                }

                GridRow {
                    InspectorLabel("Title")
                    InspectorTextField(titleBinding(task))
                }

                GridRow {
                    InspectorLabel("Status")
                    HStack(spacing: 6) {
                        Image(systemName: state.systemImage).foregroundStyle(state.color)
                        Text(state.description)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.trailing, 8)
                }

                GridRow {
                    InspectorLabel("Progress")
                    // A Blocked task's state is derived from its dependencies — it can't be changed
                    // manually until its blockers are Done (see the explanation below).
                    progressPicker(task)
                        .disabled(state == .backlog)
                }

                GridRow {
                    InspectorLabel("Priority")
                    priorityPicker(task)
                }

                GridRow {
                    InspectorLabel("Estimate")
                    InspectorTextValue(task.estimate?.displayText ?? "—")
                }

                GridRow {
                    InspectorLabel("Tags")
                    InspectorTextValue(task.tags.isEmpty ? "—" : task.tags.joined(separator: ", "))
                }

                InspectorDivider()

                GridRow {
                    InspectorLabel("Created")
                    InspectorTextValue(Self.formatted(task.createdAt))
                }

                GridRow {
                    InspectorLabel("Updated")
                    InspectorTextValue(Self.formatted(task.updatedAt))
                }
            }

            if state == .backlog {
                backlogExplanation(task)
            }

            descriptionSection(task)

            dependencySections(task)

            commentsSection(task)

            notesSection(task)
        }
    }

    // MARK: - Backlog explanation (spec §7.5)

    private func backlogExplanation(_ task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Blocked", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("This task will become Ready to Start when all blockers are Done.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .padding(.horizontal, 8)
    }

    // MARK: - Dependency sections

    @ViewBuilder
    private func dependencySections(_ task: PlanTask) -> some View {
        let blockers = viewModel.blockers(of: task)
        let prerequisites = viewModel.prerequisites(of: task)
        let dependents = viewModel.dependents(of: task)
        let unlocked = viewModel.unlockedByCompleting(task)

        VStack(alignment: .leading, spacing: 16) {
            if !blockers.isEmpty {
                taskListSection("Blocked by", tasks: blockers)
            }
            prerequisitesSection(task, prerequisites: prerequisites)
            taskListSection("Next tasks", tasks: dependents, emptyText: "Nothing depends on this task.")
            if !unlocked.isEmpty {
                taskListSection("Unlocked by completing this", tasks: unlocked)
            }
        }
        .padding(.horizontal, 8)
    }

    /// Editable "Dependencies" section: add a prerequisite from a menu, or remove existing ones.
    private func prerequisitesSection(_ task: PlanTask, prerequisites: [PlanTask]) -> some View {
        let candidates = viewModel.candidatePrerequisites(for: task)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dependencies").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    if candidates.isEmpty {
                        Text("No available tasks")
                    } else {
                        ForEach(candidates) { candidate in
                            Button(candidate.title) { viewModel.addPrerequisite(candidate, to: task) }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(candidates.isEmpty)
                .help("Add a task that must be done first")
            }

            if prerequisites.isEmpty {
                Text("This task has no dependencies.").font(.footnote).foregroundStyle(.tertiary)
            } else {
                ForEach(prerequisites) { dependency in
                    let depState = viewModel.displayState(of: dependency)
                    HStack(spacing: 7) {
                        Image(systemName: depState.systemImage).foregroundStyle(depState.color)
                        Button(dependency.title) { viewModel.selectTask(dependency.id) }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.removePrerequisite(dependency, from: task)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this dependency")
                    }
                }
            }
        }
    }

    private func taskListSection(_ title: String, tasks: [PlanTask], emptyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text("\(tasks.count)").font(.subheadline).foregroundStyle(.tertiary)
            }
            if tasks.isEmpty {
                if let emptyText {
                    Text(emptyText).font(.footnote).foregroundStyle(.tertiary)
                }
            } else {
                ForEach(tasks) { dependency in
                    let depState = viewModel.displayState(of: dependency)
                    Button {
                        viewModel.selectTask(dependency.id)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: depState.systemImage).foregroundStyle(depState.color)
                            Text(dependency.title).lineLimit(1)
                            Spacer()
                            Text(depState.description).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Description

    private func descriptionSection(_ task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description").font(.headline).foregroundStyle(.secondary)
            TextEditor(text: detailsBinding(task))
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                .overlay(alignment: .topLeading) {
                    if task.details.isEmpty {
                        Text("What does this task entail?")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Comments

    @State private var newCommentText: String = ""

    private func commentsSection(_ task: PlanTask) -> some View {
        let comments = task.comments.sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Comments").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text("\(comments.count)").font(.subheadline).foregroundStyle(.tertiary)
            }

            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(comment.author)
                            .font(.caption.weight(.semibold))
                        Text(Self.formatted(comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(comment.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                .contextMenu {
                    Button("Delete Comment", role: .destructive) {
                        viewModel.store?.deleteComment(comment)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add a comment…", text: $newCommentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { addComment(to: task) }
                Button("Add") { addComment(to: task) }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 8)
    }

    private func addComment(to task: PlanTask) {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.store?.addComment(text, author: "user", to: task)
        newCommentText = ""
    }

    // MARK: - Notes

    private func notesSection(_ task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.headline).foregroundStyle(.secondary)
            TextEditor(text: notesBinding(task))
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Pickers

    private func progressPicker(_ task: PlanTask) -> some View {
        Picker("", selection: progressBinding(task)) {
            ForEach(TaskProgress.allCases) { progress in
                Text(progress.description).tag(progress)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }

    private func priorityPicker(_ task: PlanTask) -> some View {
        Picker("", selection: priorityBinding(task)) {
            Text("None").tag(TaskPriority?.none)
            ForEach(TaskPriority.allCases) { priority in
                Text(priority.description).tag(TaskPriority?.some(priority))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }

    // MARK: - Formatting

    /// A readable date/time, e.g. "Jun 22, 2026 at 9:41 AM".
    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Bindings

    private func titleBinding(_ task: PlanTask) -> Binding<String> {
        Binding(
            get: { task.title },
            set: { task.title = $0; task.touch(); viewModel.store?.save() }
        )
    }

    private func detailsBinding(_ task: PlanTask) -> Binding<String> {
        Binding(
            get: { task.details },
            set: { task.details = $0; task.touch(); viewModel.store?.save() }
        )
    }

    private func notesBinding(_ task: PlanTask) -> Binding<String> {
        Binding(
            get: { task.notes },
            set: { task.notes = $0; task.touch(); viewModel.store?.save() }
        )
    }

    private func progressBinding(_ task: PlanTask) -> Binding<TaskProgress> {
        Binding(
            get: { task.progress },
            set: { viewModel.setProgress($0, for: task) }
        )
    }

    private func priorityBinding(_ task: PlanTask) -> Binding<TaskPriority?> {
        Binding(
            get: { task.priority },
            set: { task.priority = $0; task.touch(); viewModel.store?.save() }
        )
    }
}
