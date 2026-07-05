//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A single task card on the graph canvas. Colour-coded by derived ``TaskDisplayState`` with an
/// icon + label so state is never conveyed by colour alone (spec §8).
struct TaskCardView: View {

    let task: PlanTask
    let number: Int
    let state: TaskDisplayState
    let isSelected: Bool
    let isDimmed: Bool
    let isEditing: Bool

    @Binding var editingTitle: String
    var onCommitEdit: () -> Void

    @FocusState private var titleFieldFocused: Bool

    private var isBacklog: Bool { state == .backlog }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: state.systemImage)
                    .foregroundStyle(state.color)
                    .font(.system(size: 12, weight: .semibold))

                Text("\(number)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if isEditing {
                    TextField("Task title", text: $editingTitle, onCommit: onCommitEdit)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .focused($titleFieldFocused)
                        .onAppear { titleFieldFocused = true }
                } else {
                    Text(task.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(isBacklog ? .secondary : .primary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let category = task.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer(minLength: 0)
                if !task.details.isEmpty {
                    Label("description", systemImage: "text.alignleft")
                        .labelStyle(.iconOnly)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !task.notes.isEmpty {
                    Label("notes", systemImage: "text.bubble")
                        .labelStyle(.iconOnly)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let estimate = task.estimate {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(estimate.displayText)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if let priority = task.priority, priority == .high {
                    Image(systemName: priority.systemImage)
                        .font(.caption2)
                        .foregroundStyle(priority.color)
                }
            }
        }
        .padding(10)
        .frame(width: GraphMetrics.cardSize.width, height: GraphMetrics.cardSize.height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1.5)
        }
        .opacity(isDimmed ? 0.35 : 1)
        // Only the selected card casts a shadow — avoids N offscreen shadow passes per frame while
        // dragging. Depth for the rest comes from the border.
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: isSelected ? 8 : 0, y: isSelected ? 2 : 0)
    }

    private var backgroundFill: AnyShapeStyle {
        if isBacklog {
            return AnyShapeStyle(.background.opacity(0.6))
        }
        return AnyShapeStyle(.background)
    }

    private var borderColor: Color {
        if isSelected { return state.color }
        return isBacklog ? Color.secondary.opacity(0.4) : state.color.opacity(0.7)
    }
}
