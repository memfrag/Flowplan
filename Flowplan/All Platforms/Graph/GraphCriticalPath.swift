//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// The result of a Critical Path Method (CPM) analysis over a plan's dependency graph.
nonisolated public struct CriticalPathResult: Sendable, Equatable {
    /// Every task with zero slack — a delay on any of these pushes out the whole project.
    public var criticalTaskIDs: Set<UUID>
    /// One longest-duration chain, in dependency order (prerequisite → dependent).
    public var orderedPath: [UUID]
    /// Slack (float) per task, in the same unit as the supplied durations.
    public var slackByTask: [UUID: Double]
    /// The project's total duration (the longest weighted path), in the supplied unit.
    public var totalDuration: Double

    public var isEmpty: Bool { orderedPath.isEmpty }

    public init(
        criticalTaskIDs: Set<UUID> = [],
        orderedPath: [UUID] = [],
        slackByTask: [UUID: Double] = [:],
        totalDuration: Double = 0
    ) {
        self.criticalTaskIDs = criticalTaskIDs
        self.orderedPath = orderedPath
        self.slackByTask = slackByTask
        self.totalDuration = totalDuration
    }
}

// MARK: - Critical Path Method (spec §23, "critical path analysis")

nonisolated extension TaskGraph {

    /// Computes the critical path via CPM.
    ///
    /// - Parameter durations: each task's duration in a consistent unit (e.g. hours). Tasks absent
    ///   from the map are treated as zero-duration.
    /// - Returns: the critical task set, one ordered longest chain, per-task slack, and total duration.
    ///
    /// The forward pass computes each task's earliest finish (the longest weighted path ending at it);
    /// the backward pass computes each task's latest finish without delaying the project. Slack is the
    /// gap between them; zero-slack tasks are critical. Recursion is memoized and cycle-guarded (the
    /// graph should be a DAG, but this stays safe on malformed input).
    public func criticalPath(durations: [UUID: Double]) -> CriticalPathResult {
        let ids = taskIDs
        guard !ids.isEmpty else { return CriticalPathResult() }

        func duration(_ id: UUID) -> Double { max(0, durations[id] ?? 0) }

        // Forward pass: earliest finish.
        var earliestFinish: [UUID: Double] = [:]
        func computeEarliestFinish(_ id: UUID, visiting: Set<UUID>) -> Double {
            if let cached = earliestFinish[id] { return cached }
            guard !visiting.contains(id) else { return duration(id) }
            let start = prerequisiteIDs(of: id)
                .map { computeEarliestFinish($0, visiting: visiting.union([id])) }
                .max() ?? 0
            let finish = start + duration(id)
            earliestFinish[id] = finish
            return finish
        }
        for id in ids { _ = computeEarliestFinish(id, visiting: []) }

        let totalDuration = earliestFinish.values.max() ?? 0
        guard totalDuration > 0 else { return CriticalPathResult() }

        // Backward pass: latest finish.
        var latestFinish: [UUID: Double] = [:]
        func computeLatestFinish(_ id: UUID, visiting: Set<UUID>) -> Double {
            if let cached = latestFinish[id] { return cached }
            guard !visiting.contains(id) else { return totalDuration }
            let dependents = dependentIDs(of: id)
            let finish: Double
            if dependents.isEmpty {
                finish = totalDuration
            } else {
                finish = dependents
                    .map { computeLatestFinish($0, visiting: visiting.union([id])) - duration($0) }
                    .min() ?? totalDuration
            }
            latestFinish[id] = finish
            return finish
        }
        for id in ids { _ = computeLatestFinish(id, visiting: []) }

        // Slack and critical set.
        let epsilon = 1e-6
        var slackByTask: [UUID: Double] = [:]
        var earliestStart: [UUID: Double] = [:]
        var criticalTaskIDs: Set<UUID> = []
        for id in ids {
            let ef = earliestFinish[id] ?? duration(id)
            let lf = latestFinish[id] ?? totalDuration
            let slack = lf - ef
            slackByTask[id] = slack
            earliestStart[id] = ef - duration(id)
            if slack <= epsilon { criticalTaskIDs.insert(id) }
        }

        // Trace one ordered chain from a critical sink back through binding critical prerequisites.
        var ordered: [UUID] = []
        let criticalSinks = criticalTaskIDs.filter { id in
            dependentIDs(of: id).allSatisfy { !criticalTaskIDs.contains($0) }
        }
        if var current = criticalSinks.max(by: { (earliestFinish[$0] ?? 0) < (earliestFinish[$1] ?? 0) }) {
            ordered.append(current)
            while true {
                let start = earliestStart[current] ?? 0
                let criticalPrereqs = prerequisiteIDs(of: current).filter { criticalTaskIDs.contains($0) }
                // The binding prerequisite is the one whose finish equals this task's start.
                let binding = criticalPrereqs.first { abs((earliestFinish[$0] ?? 0) - start) <= epsilon }
                    ?? criticalPrereqs.max(by: { (earliestFinish[$0] ?? 0) < (earliestFinish[$1] ?? 0) })
                guard let next = binding else { break }
                ordered.append(next)
                current = next
            }
            ordered.reverse()
        }

        return CriticalPathResult(
            criticalTaskIDs: criticalTaskIDs,
            orderedPath: ordered,
            slackByTask: slackByTask,
            totalDuration: totalDuration
        )
    }
}
