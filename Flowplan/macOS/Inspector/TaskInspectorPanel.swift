//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import MarkdownUI

/// The right-hand inspector for the selected task (spec §7.5). Built from SwiftUIToolbox's
/// inspector grid components, with custom dependency sections below.
struct TaskInspectorPanel: View {

    @Bindable var viewModel: PlanViewModel

    /// The narrow sidebar inspector (`.column`) or the wider pop-out editor window (`.wide`).
    var layout: Layout = .column

    enum Layout { case column, wide }

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let task = viewModel.selectedTask {
            switch layout {
            case .column:
                ScrollView {
                    content(for: task)
                        .padding(.vertical, 8)
                }
            case .wide:
                wideContent(for: task)
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
    /// The narrow single-column layout used by the sidebar inspector.
    private func content(for task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)
        return VStack(alignment: .leading, spacing: 16) {
            fieldsSection(task, state: state)
            descriptionSection(task)
            dependencySections(task)
            commentsSection(task)
            notesSection(task)
        }
    }

    /// The two-column layout used by the pop-out editor window (see ``TaskEditorWindow``): fields and
    /// free text on the left, relationships and comments on the right, each independently scrollable.
    private func wideContent(for task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)
        return HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldsSection(task, state: state)
                    descriptionSection(task)
                    notesSection(task)
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dependencySections(task)
                    commentsSection(task)
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func fieldsSection(_ task: PlanTask, state: TaskDisplayState) -> some View {
        InspectorGrid {
            InspectorSectionHeader("Task")
                .overlay(alignment: .trailing) {
                    // Only offer "pop out to a window" from the narrow inspector — no point from the
                    // window itself.
                    if layout == .column {
                        Button {
                            openWindow(id: TaskEditorWindow.windowID, value: task.id)
                        } label: {
                            Image(systemName: "macwindow")
                        }
                        .buttonStyle(.borderless)
                        .help("Open this task in a separate window")
                        .padding(.trailing, 8)
                    }
                }

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
                InspectorLabel("Due Date")
                dueDateControl(task)
            }

            if task.dueDate != nil {
                GridRow {
                    InspectorLabel("Calendar")
                    CalendarButton(task: task) { message in
                        viewModel.activeAlert = PlanAlert(title: "Calendar", message: message)
                    }
                }
            }

            GridRow {
                InspectorLabel("Tags")
                InspectorTextField(tagsBinding(task))
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

    @State private var descriptionPreview = false
    @State private var notesPreview = false

    private func descriptionSection(_ task: PlanTask) -> some View {
        markdownEditor(
            title: "Description",
            text: detailsBinding(task),
            isPreview: $descriptionPreview,
            minHeight: 90,
            placeholder: "What does this task entail?"
        )
    }

    /// A text area with an Edit/Preview toggle: raw editing via `TextEditor`, or a MarkdownUI
    /// rendering of the same text.
    @ViewBuilder
    private func markdownEditor(
        title: String,
        text: Binding<String>,
        isPreview: Binding<Bool>,
        minHeight: CGFloat,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: isPreview) {
                    Image(systemName: "pencil").tag(false)
                    Image(systemName: "eye").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Switch between editing and a Markdown preview")
            }

            if isPreview.wrappedValue {
                markdownView(text.wrappedValue, placeholder: placeholder)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
            } else {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    .overlay(alignment: .topLeading) {
                        if text.wrappedValue.isEmpty {
                            Text(placeholder)
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(.horizontal, 8)
    }

    /// Renders `text` as Markdown, falling back to plain text if it can't be parsed and to a muted
    /// placeholder when empty.
    @ViewBuilder
    private func markdownView(_ text: String, placeholder: String) -> some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(placeholder).font(.body).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let document = try? MarkdownDocument(text) {
            Markdown(document, lazy: false)
                .tint(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    markdownView(comment.text, placeholder: "")
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
        markdownEditor(
            title: "Notes",
            text: notesBinding(task),
            isPreview: $notesPreview,
            minHeight: 80,
            placeholder: "Additional notes…"
        )
    }

    // MARK: - Due date

    @ViewBuilder
    private func dueDateControl(_ task: PlanTask) -> some View {
        HStack(spacing: 6) {
            if task.dueDate != nil {
                DatePicker("", selection: dueDateBinding(task), displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                if task.isOverdue {
                    Text("Overdue")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button {
                    // Clearing the due date also removes any calendar event mirroring it.
                    try? CalendarService.shared.removeEvent(for: task)
                    viewModel.store?.updateTask(task, dueDate: .some(nil))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear due date")
            } else {
                Button("Set Due Date…") {
                    let today = Calendar.current.startOfDay(for: .now)
                    viewModel.store?.updateTask(task, dueDate: .some(today))
                }
                .buttonStyle(.link)
                Spacer()
            }
        }
        .padding(.trailing, 8)
    }

    private func dueDateBinding(_ task: PlanTask) -> Binding<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        return taskBinding(task, default: today, get: { $0.dueDate ?? today }) { task, value in
            viewModel.store?.updateTask(task, dueDate: .some(value))
        }
    }

    /// Adds/removes a Calendar event mirroring the task's due date (see ``CalendarService``).
    private struct CalendarButton: View {
        let task: PlanTask
        let onError: (String) -> Void

        @State private var inCalendar = false
        @State private var working = false

        var body: some View {
            HStack {
                Button {
                    Task { await toggle() }
                } label: {
                    Label(inCalendar ? "Remove from Calendar" : "Add to Calendar",
                          systemImage: inCalendar ? "calendar.badge.minus" : "calendar.badge.plus")
                }
                .buttonStyle(.link)
                .disabled(working)
                Spacer()
            }
            .padding(.trailing, 8)
            .task(id: task.id) { inCalendar = CalendarService.shared.hasEvent(for: task) }
        }

        private func toggle() async {
            working = true
            defer { working = false }
            let service = CalendarService.shared
            do {
                if inCalendar {
                    try service.removeEvent(for: task)
                    inCalendar = false
                } else {
                    guard await service.requestAccess() else {
                        onError(CalendarService.CalendarError.accessDenied.errorDescription ?? "Calendar access was denied.")
                        return
                    }
                    try service.addOrUpdateEvent(for: task)
                    inCalendar = service.hasEvent(for: task)
                }
            } catch {
                onError(error.localizedDescription)
            }
        }
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

    /// A binding over a task looked up **by id** on every access, so it never dereferences a task
    /// that was deleted while the inspector was still mounted — reading a deleted SwiftData model
    /// traps (see the delete-ordering fix in PlanViewModel). Returns `fallback` once the task is gone.
    private func taskBinding<Value>(
        _ task: PlanTask,
        default fallback: Value,
        get: @escaping (PlanTask) -> Value,
        set: @escaping (PlanTask, Value) -> Void
    ) -> Binding<Value> {
        let id = task.id
        return Binding(
            get: { viewModel.task(id: id).map(get) ?? fallback },
            set: { newValue in
                guard let task = viewModel.task(id: id) else { return }
                set(task, newValue)
            }
        )
    }

    private func titleBinding(_ task: PlanTask) -> Binding<String> {
        taskBinding(task, default: "", get: { $0.title }) { task, value in
            task.title = value; task.touch(); viewModel.store?.save()
        }
    }

    private func detailsBinding(_ task: PlanTask) -> Binding<String> {
        taskBinding(task, default: "", get: { $0.details }) { task, value in
            task.details = value; task.touch(); viewModel.store?.save()
        }
    }

    private func notesBinding(_ task: PlanTask) -> Binding<String> {
        taskBinding(task, default: "", get: { $0.notes }) { task, value in
            task.notes = value; task.touch(); viewModel.store?.save()
        }
    }

    /// Edits tags as a comma-separated string; parses into trimmed, de-duplicated, non-empty tags.
    private func tagsBinding(_ task: PlanTask) -> Binding<String> {
        taskBinding(task, default: "", get: { $0.tags.joined(separator: ", ") }) { task, newValue in
            var seen = Set<String>()
            task.tags = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            task.touch()
            viewModel.store?.save()
        }
    }

    private func progressBinding(_ task: PlanTask) -> Binding<TaskProgress> {
        taskBinding(task, default: .notStarted, get: { $0.progress }) { task, value in
            viewModel.setProgress(value, for: task)
        }
    }

    private func priorityBinding(_ task: PlanTask) -> Binding<TaskPriority?> {
        taskBinding(task, default: nil, get: { $0.priority }) { task, value in
            task.priority = value; task.touch(); viewModel.store?.save()
        }
    }
}
