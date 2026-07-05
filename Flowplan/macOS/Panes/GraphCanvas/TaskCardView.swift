//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A single task card on the graph canvas. Colour-coded by derived ``TaskDisplayState`` with an
/// icon + label so state is never conveyed by colour alone (spec §8).
struct TaskCardView: View {

    /// How this card should be highlighted as the drop target of an in-progress dependency drag.
    enum LinkTargetHighlight: Equatable {
        case none
        /// A valid destination — dropping here would create a dependency.
        case valid
        /// The pointer is over this card, but the dependency would be rejected (self/duplicate/cycle).
        case invalid
    }

    let task: PlanTask
    let number: Int
    let state: TaskDisplayState
    let isSelected: Bool
    let isDimmed: Bool
    let isEditing: Bool
    var linkTarget: LinkTargetHighlight = .none

    @Binding var editingTitle: String
    var onCommitEdit: () -> Void

    @FocusState private var titleFieldFocused: Bool

    private var isBacklog: Bool { state == .backlog }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            leadingColumn

            VStack(alignment: .leading, spacing: 5) {
                if isEditing {
                    TextField("Task title", text: $editingTitle, onCommit: onCommitEdit)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .focused($titleFieldFocused)
                        .onAppear { titleFieldFocused = true }
                } else {
                    Text(task.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(isBacklog ? .secondary : .primary)
                }

                Spacer(minLength: 2)

                if hasBottomMetadata {
                    bottomMetadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(width: GraphMetrics.cardSize.width, height: GraphMetrics.cardSize.height, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1.5)
        }
        .overlay {
            // A bold ring around the card the connector is currently pointing at, so the drop
            // destination is unmistakable while dragging.
            if let color = linkTargetColor {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color, lineWidth: 3)
            }
        }
        .opacity(isDimmed ? 0.35 : 1)
        // Only the selected card — or the current link target — casts a shadow, so we avoid N
        // offscreen shadow passes per frame while dragging. Depth for the rest comes from the border.
        .shadow(color: linkTargetColor ?? .black.opacity(isSelected ? 0.18 : 0),
                radius: linkTarget == .none ? (isSelected ? 8 : 0) : 10,
                y: isSelected ? 2 : 0)
    }

    /// The leading vertical column: state icon, number, then notes/description indicators.
    private var leadingColumn: some View {
        VStack(spacing: 5) {
            Image(systemName: state.systemImage)
                .foregroundStyle(state.color)
                .font(.system(size: 14, weight: .semibold))

            Text("\(number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            if !task.details.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Has a description")
            }
            if !task.notes.isEmpty {
                Image(systemName: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Has notes")
            }
        }
        .frame(width: 20)
    }

    private var hasBottomMetadata: Bool {
        (task.category?.isEmpty == false) || task.estimate != nil || task.priority == .high
    }

    private var bottomMetadata: some View {
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
            if let priority = task.priority, priority == .high {
                Image(systemName: priority.systemImage)
                    .font(.caption2)
                    .foregroundStyle(priority.color)
            }
        }
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

    /// The ring/glow colour for the current drop-target state, or `nil` when this card isn't the target.
    private var linkTargetColor: Color? {
        switch linkTarget {
        case .none: return nil
        case .valid: return .green
        case .invalid: return .red
        }
    }
}
