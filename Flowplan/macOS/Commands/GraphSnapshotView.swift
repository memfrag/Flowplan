//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A static rendering of a plan's graph, used by `ImageRenderer` to export a PNG (spec §18.1).
struct GraphSnapshotView: View {

    let plan: Plan

    private let cardSize = GraphMetrics.cardSize
    private let padding: CGFloat = 60

    private var orderedTasks: [PlanTask] {
        plan.tasks.sorted { $0.createdAt < $1.createdAt }
    }

    private var bounds: CGRect {
        let points = orderedTasks.compactMap { $0.position }
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 400, height: 300) }
        var rect = CGRect(origin: first, size: .zero)
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect.insetBy(dx: -(cardSize.width / 2 + padding), dy: -(cardSize.height / 2 + padding))
    }

    var body: some View {
        let origin = bounds.origin
        let graph = plan.graph

        ZStack {
            Color(white: 0.98)

            DependencyEdgesView(
                edges: edges(origin: origin),
                pendingLink: nil,
                frameRect: CGRect(origin: .zero, size: bounds.size)
            )

            ForEach(Array(orderedTasks.enumerated()), id: \.element.id) { index, task in
                TaskCardView(
                    task: task,
                    number: index + 1,
                    state: graph.displayState(of: task.id),
                    isSelected: false,
                    isDimmed: false,
                    isEditing: false,
                    editingTitle: .constant(""),
                    onCommitEdit: {}
                )
                .position(shifted(task.position ?? .zero, by: origin))
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private func shifted(_ point: CGPoint, by origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func edges(origin: CGPoint) -> [DependencyEdgesView.Edge] {
        plan.dependencies.compactMap { dependency in
            guard let from = plan.task(id: dependency.prerequisiteTaskID),
                  let to = plan.task(id: dependency.dependentTaskID),
                  let fromPos = from.position, let toPos = to.position else { return nil }
            let start = CGPoint(x: fromPos.x + cardSize.width / 2, y: fromPos.y)
            let end = CGPoint(x: toPos.x - cardSize.width / 2, y: toPos.y)
            return DependencyEdgesView.Edge(
                id: dependency.id,
                start: shifted(start, by: origin),
                end: shifted(end, by: origin),
                isHighlighted: false
            )
        }
    }
}
