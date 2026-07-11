//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A list of the active plan's tasks, grouped by derived state, for quick scanning and metadata
/// editing (spec §12).
struct PlanListView: View {

    @Bindable var viewModel: PlanViewModel

    /// The order sections appear in — actionable work first, archived last.
    private let sectionOrder: [TaskDisplayState] = [.inProgress, .readyToStart, .backlog, .done, .closed]

    /// Filtered tasks grouped by display state, built from a single graph snapshot.
    private var groups: [TaskDisplayState: [PlanTask]] {
        guard let graph = viewModel.plan?.graph else { return [:] }
        var result: [TaskDisplayState: [PlanTask]] = [:]
        for task in viewModel.tasks {
            let state = graph.displayState(of: task.id)
            guard viewModel.matches(task, displayState: state) else { continue }
            result[state, default: []].append(task)
        }
        return result
    }

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(sectionOrder, id: \.self) { state in
                let items = groups[state] ?? []
                if !items.isEmpty {
                    Section {
                        ForEach(items) { task in
                            row(task)
                                .tag(task.id)
                                .contextMenu { rowContextMenu(task) }
                        }
                    } header: {
                        sectionHeader(state, count: items.count)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionHeader(_ state: TaskDisplayState, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: state.systemImage).foregroundStyle(state.color)
            Text(state.description)
            Text("\(count)").foregroundStyle(.tertiary).monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder
    private func rowContextMenu(_ task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)
        if state == .closed || state == .done {
            Button("Reopen") { viewModel.reopen(task) }
        } else {
            Button("Close") { viewModel.close(task) }
        }
        Button("Duplicate") {
            viewModel.selectTask(task.id)
            viewModel.duplicateSelectedTask()
        }
        Divider()
        Button("Delete", role: .destructive) {
            viewModel.selectTask(task.id)
            viewModel.deleteSelectedTaskOrDependency()
        }
    }

    private func row(_ task: PlanTask) -> some View {
        HStack(spacing: 12) {
            Text("\(task.number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
                .help("Task ID")

            Text(task.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: progressBinding(task)) {
                ForEach(TaskProgress.allCases) { progress in
                    Text(progress.description).tag(progress)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120, alignment: .leading)

            Text("\(viewModel.blockers(of: task).count)")
                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                .help("Blockers")
            Text("\(viewModel.prerequisites(of: task).count)")
                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                .help("Dependencies")
            Text("\(viewModel.dependents(of: task).count)")
                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                .help("Dependents")

            Group {
                if let priority = task.priority {
                    Label(priority.description, systemImage: priority.systemImage)
                        .foregroundStyle(priority.color)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 90, alignment: .leading)

            Text(task.estimate?.displayText ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Group {
                if task.dueDate != nil {
                    DueDateBadge(task: task)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 80, alignment: .leading)
        }
        .lineLimit(1)
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedTaskID },
            set: { viewModel.selectTask($0) }
        )
    }

    private func progressBinding(_ task: PlanTask) -> Binding<TaskProgress> {
        Binding(
            get: { task.progress },
            set: { viewModel.setProgress($0, for: task) }
        )
    }
}
