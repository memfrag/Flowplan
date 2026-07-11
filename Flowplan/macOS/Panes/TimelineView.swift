//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A chronological timeline of the active plan's tasks, grouped into horizontal columns by due date:
/// a leading "Overdue" column, one column per day that has tasks, and a trailing "No Due Date"
/// column. Closed tasks are omitted. Cards are click-to-select; the inspector shows details.
struct PlanTimelineView: View {

    @Bindable var viewModel: PlanViewModel

    var body: some View {
        let columns = buildColumns()

        if columns.isEmpty {
            ContentUnavailableView(
                "No tasks to schedule",
                systemImage: "calendar",
                description: Text("Give tasks a due date to see them on the timeline.")
            )
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { column in
                        columnView(column)
                    }
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Column

    private func columnView(_ column: TimelineColumn) -> some View {
        VStack(spacing: 0) {
            header(column)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(column.tasks) { task in
                        card(task, showsDate: column.isOverdue)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(column.isOverdue ? Color.red.opacity(0.06) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(columnBorderColor(column), lineWidth: column.isToday ? 2 : 1)
        )
    }

    private func header(_ column: TimelineColumn) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(column.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(column.isOverdue ? Color.red : .primary)
                Spacer()
                Text("\(column.tasks.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let subtitle = column.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(column.isToday ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func columnBorderColor(_ column: TimelineColumn) -> Color {
        if column.isToday { return .accentColor }
        if column.isOverdue { return .red.opacity(0.4) }
        return .primary.opacity(0.08)
    }

    // MARK: - Card

    private func card(_ task: PlanTask, showsDate: Bool) -> some View {
        let state = viewModel.displayState(of: task)
        return VStack(alignment: .leading, spacing: 6) {
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

            if showsDate {
                DueDateBadge(task: task)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(viewModel.isSelected(task.id) ? state.color : state.color.opacity(0.35),
                              lineWidth: viewModel.isSelected(task.id) ? 2.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectTask(task.id) }
    }

    // MARK: - Grouping

    private func buildColumns() -> [TimelineColumn] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tasks = viewModel.tasks.filter { $0.progress != .closed }

        let overdue = tasks.filter { $0.isOverdue }
        let overdueIDs = Set(overdue.map(\.id))
        let dated = tasks.filter { $0.dueDate != nil && !overdueIDs.contains($0.id) }
        let undated = tasks.filter { $0.dueDate == nil }

        var byDay: [Date: [PlanTask]] = [:]
        for task in dated {
            let day = calendar.startOfDay(for: task.dueDate!)
            byDay[day, default: []].append(task)
        }

        var columns: [TimelineColumn] = []

        if !overdue.isEmpty {
            columns.append(TimelineColumn(
                id: "overdue",
                title: "Overdue",
                subtitle: nil,
                tasks: overdue.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) },
                isToday: false,
                isOverdue: true
            ))
        }

        for day in byDay.keys.sorted() {
            let tasksForDay = (byDay[day] ?? []).sorted { lhs, rhs in
                let lp = priorityRank(lhs.priority), rp = priorityRank(rhs.priority)
                if lp != rp { return lp > rp }
                return lhs.number < rhs.number
            }
            columns.append(TimelineColumn(
                id: "day-\(day.timeIntervalSince1970)",
                title: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                subtitle: relativeLabel(for: day, today: today, calendar: calendar),
                tasks: tasksForDay,
                isToday: calendar.isDate(day, inSameDayAs: today),
                isOverdue: false
            ))
        }

        if !undated.isEmpty {
            columns.append(TimelineColumn(
                id: "undated",
                title: "No Due Date",
                subtitle: nil,
                tasks: undated,
                isToday: false,
                isOverdue: false
            ))
        }

        return columns
    }

    private func relativeLabel(for day: Date, today: Date, calendar: Calendar) -> String? {
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return "In \(days) days"
        default: return nil
        }
    }

    private func priorityRank(_ priority: TaskPriority?) -> Int {
        switch priority {
        case .high: 2
        case .medium: 1
        case .low: 0
        case nil: -1
        }
    }
}

private struct TimelineColumn: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let tasks: [PlanTask]
    let isToday: Bool
    let isOverdue: Bool
}
