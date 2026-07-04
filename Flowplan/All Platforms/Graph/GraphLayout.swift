//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics

/// Spacing parameters for the layered auto-layout.
nonisolated public struct GraphLayoutMetrics: Sendable {
    public var columnSpacing: CGFloat
    public var rowSpacing: CGFloat
    public var origin: CGPoint

    public init(columnSpacing: CGFloat = 240, rowSpacing: CGFloat = 130, origin: CGPoint = CGPoint(x: 120, y: 100)) {
        self.columnSpacing = columnSpacing
        self.rowSpacing = rowSpacing
        self.origin = origin
    }
}

// MARK: - Layered topological layout (spec §9.2)

nonisolated extension TaskGraph {

    /// Assigns each task to a layer (column) by its longest dependency depth.
    ///
    /// Tasks with no prerequisites are in layer 0; every other task sits one column to the right
    /// of its deepest prerequisite. Order is deterministic given a stable task ordering.
    public func layers(orderedTaskIDs: [UUID]) -> [UUID: Int] {
        var layerByTask: [UUID: Int] = [:]

        func layer(of taskID: UUID, visiting: Set<UUID>) -> Int {
            if let cached = layerByTask[taskID] { return cached }
            // Guard against cycles defensively (the graph should be a DAG).
            guard !visiting.contains(taskID) else { return 0 }

            let prerequisites = prerequisiteIDs(of: taskID)
            let computed: Int
            if prerequisites.isEmpty {
                computed = 0
            } else {
                computed = 1 + prerequisites.map { layer(of: $0, visiting: visiting.union([taskID])) }.max()!
            }
            layerByTask[taskID] = computed
            return computed
        }

        for taskID in orderedTaskIDs {
            _ = layer(of: taskID, visiting: [])
        }
        return layerByTask
    }

    /// Computes left→right positions for the given tasks using a layered topological layout.
    ///
    /// - Parameters:
    ///   - orderedTaskIDs: Tasks in a stable display order (used to break ties within a layer).
    ///   - metrics: Spacing/origin parameters.
    /// - Returns: A position for every supplied task id.
    public func layeredPositions(
        orderedTaskIDs: [UUID],
        metrics: GraphLayoutMetrics = GraphLayoutMetrics()
    ) -> [UUID: CGPoint] {
        let layerByTask = layers(orderedTaskIDs: orderedTaskIDs)

        // Bucket tasks by layer, preserving the supplied order for vertical stacking.
        var tasksByLayer: [Int: [UUID]] = [:]
        for taskID in orderedTaskIDs {
            let layer = layerByTask[taskID] ?? 0
            tasksByLayer[layer, default: []].append(taskID)
        }

        var positions: [UUID: CGPoint] = [:]
        for (layer, tasksInLayer) in tasksByLayer {
            // Vertically centre each column around the origin row.
            let totalHeight = CGFloat(max(tasksInLayer.count - 1, 0)) * metrics.rowSpacing
            let startY = metrics.origin.y - totalHeight / 2
            for (row, taskID) in tasksInLayer.enumerated() {
                positions[taskID] = CGPoint(
                    x: metrics.origin.x + CGFloat(layer) * metrics.columnSpacing,
                    y: startY + CGFloat(row) * metrics.rowSpacing
                )
            }
        }
        return positions
    }
}
