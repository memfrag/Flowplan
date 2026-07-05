//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A summary dashboard for the active plan: status tiles plus focused lists of what's ready,
/// in progress, and blocked. Everything is a shortcut into the graph or a focus filter.
struct OverviewPane: View {

    @Bindable var viewModel: PlanViewModel

    private var tasks: [PlanTask] { viewModel.tasks }

    /// Tasks grouped by derived state, built from a single graph snapshot.
    private var groups: [TaskDisplayState: [PlanTask]] {
        guard let graph = viewModel.plan?.graph else { return [:] }
        return Dictionary(grouping: tasks) { graph.displayState(of: $0.id) }
    }

    private let tiles: [(state: TaskDisplayState, label: String)] = [
        (.readyToStart, "Ready"),
        (.inProgress, "In Progress"),
        (.backlog, "Blocked"),
        (.done, "Done"),
        (.closed, "Closed")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                if tasks.isEmpty {
                    emptyState
                } else {
                    statTiles
                    taskSection("Ready to start", state: .readyToStart,
                                empty: "Nothing is ready to start — complete blockers to unlock more.")
                    taskSection("In progress", state: .inProgress,
                                empty: "No tasks in progress.")
                    blockedSection
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.plan?.title ?? "Overview")
                .font(.largeTitle.bold())
            Text(summaryLine)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryLine: String {
        let total = tasks.count
        let ready = groups[.readyToStart]?.count ?? 0
        let inProgress = groups[.inProgress]?.count ?? 0
        let done = groups[.done]?.count ?? 0
        return "\(total) task\(total == 1 ? "" : "s") · \(ready) ready · \(inProgress) in progress · \(done) done"
    }

    // MARK: - Stat tiles

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
            ForEach(tiles, id: \.state) { tile in
                Button {
                    viewModel.focus(on: tile.state)
                } label: {
                    statTile(state: tile.state, label: tile.label, count: groups[tile.state]?.count ?? 0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statTile(state: TaskDisplayState, label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(count)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(count == 0 ? .secondary : .primary)
            Label(label, systemImage: state.systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(state.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(state.color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Sections

    private func taskSection(_ title: String, state: TaskDisplayState, empty: String) -> some View {
        let items = groups[state] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title, count: items.count)
            if items.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(items) { taskRow($0) }
            }
        }
    }

    @ViewBuilder
    private var blockedSection: some View {
        let items = groups[.backlog] ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Blocked", count: items.count)
                ForEach(items) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        taskRow(task)
                        let blockers = viewModel.blockers(of: task)
                        if !blockers.isEmpty {
                            Text("Blocked by \(blockers.map(\.title).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 24)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Text("\(count)").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func taskRow(_ task: PlanTask) -> some View {
        let state = viewModel.displayState(of: task)
        return Button {
            viewModel.openTaskInGraph(task)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: state.systemImage).foregroundStyle(state.color)
                Text(task.title).lineLimit(1)
                Spacer()
                if let estimate = task.estimate {
                    Text(estimate.displayText).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No tasks yet")
                .font(.title3.weight(.semibold))
            Text("Add a task to start building your plan.")
                .foregroundStyle(.secondary)
            Button {
                viewModel.createTaskAtViewportCenter()
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }
}
