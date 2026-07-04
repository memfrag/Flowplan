//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A list of the active plan's tasks for quick scanning and metadata editing (spec §12).
struct PlanListView: View {

    @Bindable var viewModel: PlanViewModel

    private var rows: [PlanTask] {
        viewModel.tasks.filter { viewModel.matchesFilters($0) }
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(rows) { task in
                    row(task).tag(task.id)
                }
            } header: {
                header
            }
        }
        .listStyle(.inset)
        .navigationTitle(viewModel.plan?.title ?? "Flowplan")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            Text("State").frame(width: 130, alignment: .leading)
            Text("Progress").frame(width: 120, alignment: .leading)
            Text("Blk").frame(width: 36, alignment: .trailing)
            Text("Dep").frame(width: 36, alignment: .trailing)
            Text("Next").frame(width: 36, alignment: .trailing)
            Text("Priority").frame(width: 90, alignment: .leading)
            Text("Estimate").frame(width: 80, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func row(_ task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)
        return HStack(spacing: 12) {
            Text(task.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Label(state.description, systemImage: state.systemImage)
                .foregroundStyle(state.color)
                .frame(width: 130, alignment: .leading)

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
            Text("\(viewModel.prerequisites(of: task).count)")
                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            Text("\(viewModel.dependents(of: task).count)")
                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)

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
