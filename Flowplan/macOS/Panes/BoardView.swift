//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A Kanban board of the active plan's tasks, one column per derived ``TaskDisplayState`` (spec §13).
/// Cards are dragged between columns to change status, subject to the spec's transition rules
/// (enforced by ``PlanViewModel/moveTask(_:toBoardColumn:)``).
struct PlanBoardView: View {

    @Bindable var viewModel: PlanViewModel

    /// The column a drag is currently hovering over, for the drop highlight.
    @State private var dropTarget: TaskDisplayState?

    /// Columns left-to-right, following the natural Backlog → Done → Closed flow.
    private let columns: [TaskDisplayState] = [.backlog, .readyToStart, .inProgress, .done, .closed]

    /// Tasks grouped by display state, filtered by the active search/focus, from one graph snapshot.
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
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns) { state in
                    column(state)
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Column

    private func column(_ state: TaskDisplayState) -> some View {
        let items = groups[state] ?? []
        // Backlog is derived and can't be a drop target (spec §13), so it never highlights.
        let isDropTarget = dropTarget == state && state != .backlog

        return VStack(spacing: 0) {
            columnHeader(state, count: items.count)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(items) { task in
                        card(task, state: state)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDropTarget ? state.color : Color.primary.opacity(0.08),
                              lineWidth: isDropTarget ? 2 : 1)
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let idString = ids.first,
                  let uuid = UUID(uuidString: idString),
                  let task = viewModel.task(id: uuid) else { return false }
            return viewModel.moveTask(task, toBoardColumn: state)
        } isTargeted: { targeted in
            if targeted { dropTarget = state }
            else if dropTarget == state { dropTarget = nil }
        }
    }

    private func columnHeader(_ state: TaskDisplayState, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: state.systemImage).foregroundStyle(state.color)
            Text(state.description).font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Card

    @ViewBuilder
    private func card(_ task: PlanTask, state: TaskDisplayState) -> some View {
        let content = BoardTaskCard(task: task, state: state, isSelected: viewModel.isSelected(task.id))
            .onTapGesture { viewModel.selectTask(task.id) }
            .contextMenu { cardContextMenu(task, state: state) }

        // A Blocked task's state is derived from its dependencies, so it can't be dragged to another
        // column — it moves on its own once its blockers are Done.
        if state == .backlog {
            content
        } else {
            content.draggable(task.id.uuidString) {
                BoardTaskCard(task: task, state: state, isSelected: false)
                    .frame(width: 236)
            }
        }
    }

    @ViewBuilder
    private func cardContextMenu(_ task: PlanTask, state: TaskDisplayState) -> some View {
        // Blocked tasks have a derived state — no manual status changes, only duplicate/delete.
        if state != .backlog {
            if state != .readyToStart, state != .inProgress {
                Button("Mark In Progress") { viewModel.moveTask(task, toBoardColumn: .inProgress) }
            }
            if state == .readyToStart {
                Button("Start") { viewModel.start(task) }
            }
            if state != .done {
                Button("Mark Done") { viewModel.markDone(task) }
            }
            if state == .done || state == .closed || state == .inProgress {
                Button("Mark Not Started") { viewModel.reopen(task) }
            }
            if state != .closed {
                Button("Close") { viewModel.close(task) }
            }

            Divider()
        }

        Button("Duplicate") {
            viewModel.selectTask(task.id)
            viewModel.duplicateSelectedTask()
        }
        Button("Delete", role: .destructive) {
            viewModel.selectTask(task.id)
            viewModel.deleteSelectedTaskOrDependency()
        }
    }
}

/// A compact task card for the board, colour-coded by state with the same metadata cues as the graph.
private struct BoardTaskCard: View {

    let task: PlanTask
    let state: TaskDisplayState
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state.systemImage)
                    .font(.caption)
                    .foregroundStyle(state.color)
                Text("\(task.number)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if task.priority == .high {
                    Image(systemName: TaskPriority.high.systemImage)
                        .font(.caption2)
                        .foregroundStyle(TaskPriority.high.color)
                }
            }

            Text(task.title.isEmpty ? "Untitled Task" : task.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(state == .backlog ? .secondary : .primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if hasBottomMetadata {
                HStack(spacing: 8) {
                    if let category = task.category, !category.isEmpty {
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                    Spacer(minLength: 0)
                    if let estimate = task.estimate {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text(estimate.displayText)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? state.color : state.color.opacity(0.35),
                              lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: isSelected ? 6 : 0, y: 1)
        .contentShape(Rectangle())
    }

    private var hasBottomMetadata: Bool {
        (task.category?.isEmpty == false) || task.estimate != nil
    }
}
