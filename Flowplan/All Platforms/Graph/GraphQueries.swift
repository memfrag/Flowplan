//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

// MARK: - Neighbour & readiness queries (spec §5.4)

nonisolated extension TaskGraph {

    /// Identifiers of tasks that must be completed before `taskID` (its direct prerequisites).
    public func prerequisiteIDs(of taskID: UUID) -> [UUID] {
        edges.filter { $0.dependentTaskID == taskID }.map(\.prerequisiteTaskID)
    }

    /// Identifiers of tasks that directly depend on `taskID`.
    public func dependentIDs(of taskID: UUID) -> [UUID] {
        edges.filter { $0.prerequisiteTaskID == taskID }.map(\.dependentTaskID)
    }

    /// Prerequisites of `taskID` that are not yet Done — i.e. what is currently blocking it.
    public func blockerIDs(of taskID: UUID) -> [UUID] {
        prerequisiteIDs(of: taskID).filter { progress(of: $0) != .done }
    }

    /// Whether `taskID` is currently Ready to Start.
    public func isReadyToStart(_ taskID: UUID) -> Bool {
        displayState(of: taskID) == .readyToStart
    }

    /// Dependents of `taskID` that would become Ready to Start if `taskID` were marked Done.
    ///
    /// A dependent qualifies when it is not started, not already actionable, and `taskID` is its
    /// only remaining unfinished prerequisite.
    public func unlockedByCompleting(_ taskID: UUID) -> [UUID] {
        guard progress(of: taskID) != .done else { return [] }

        return dependentIDs(of: taskID).filter { dependentID in
            guard progress(of: dependentID) == .notStarted else { return false }
            let remainingBlockers = blockerIDs(of: dependentID).filter { $0 != taskID }
            return remainingBlockers.isEmpty
        }
    }
}
