//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// A pure, `Sendable` view over a plan's tasks and dependencies.
///
/// `TaskGraph` deliberately knows nothing about SwiftData or SwiftUI: it operates on task
/// identifiers, a `progress` map, and dependency edges. This keeps the core graph logic
/// (display-state derivation, readiness, cycle detection, layout) trivially unit-testable.
///
/// Build one from a ``Plan`` via ``Plan/graph``.
nonisolated public struct TaskGraph: Sendable {

    /// Manual progress for every task, keyed by task id.
    public let progressByTask: [UUID: TaskProgress]

    /// Directed dependency edges: `prerequisite ───▶ dependent`.
    public let edges: [DependencyEdge]

    public init(progressByTask: [UUID: TaskProgress], edges: [DependencyEdge]) {
        self.progressByTask = progressByTask
        self.edges = edges
    }

    /// All task identifiers in the graph.
    public var taskIDs: Set<UUID> {
        Set(progressByTask.keys)
    }

    /// The stored progress for a task, defaulting to `.notStarted` if unknown.
    public func progress(of taskID: UUID) -> TaskProgress {
        progressByTask[taskID] ?? .notStarted
    }

    /// Derives the user-facing display state for a task (spec §4.3).
    ///
    /// - A closed task is `.closed`; a done task is `.done`.
    /// - An unresolved task with any unresolved prerequisite is `.backlog`.
    /// - Otherwise the display state follows the stored progress.
    /// A resolved prerequisite (done **or** closed) no longer blocks its dependents.
    public func displayState(of taskID: UUID) -> TaskDisplayState {
        let progress = progress(of: taskID)
        if progress == .closed { return .closed }
        if progress == .done { return .done }

        let hasUnresolvedPrerequisite = prerequisiteIDs(of: taskID).contains { !self.progress(of: $0).isResolved }
        if hasUnresolvedPrerequisite {
            return .backlog
        }

        switch progress {
        case .notStarted: return .readyToStart
        case .inProgress: return .inProgress
        case .done: return .done
        case .closed: return .closed
        }
    }
}
