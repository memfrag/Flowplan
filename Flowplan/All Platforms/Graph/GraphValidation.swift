//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// The reason a proposed dependency is invalid.
nonisolated public enum DependencyValidationError: Error, Equatable, Sendable {
    case selfDependency
    case duplicate
    case cycle

    /// The project was deleted underneath the editor — typically a deletion synced from another
    /// device — so there is nothing left to add the dependency to.
    case planUnavailable

    /// A user-facing title for an alert (spec §16).
    public var title: String {
        switch self {
        case .selfDependency: "A task cannot depend on itself."
        case .duplicate: "That dependency already exists."
        case .cycle: "Cannot create dependency"
        case .planUnavailable: "This project is no longer available"
        }
    }

    /// A user-facing message for an alert.
    public var message: String {
        switch self {
        case .selfDependency: "Choose a different prerequisite task."
        case .duplicate: "These two tasks are already connected."
        case .cycle: "This dependency would create a cycle."
        case .planUnavailable: "It was deleted, possibly on another device."
        }
    }
}

// MARK: - Cycle detection & validation (spec §5.3, §21)

nonisolated extension TaskGraph {

    /// Whether `targetID` is reachable from `startID` by following dependency edges
    /// (prerequisite ───▶ dependent).
    public func isReachable(from startID: UUID, to targetID: UUID) -> Bool {
        var visited = Set<UUID>()
        var stack = [startID]

        while let current = stack.popLast() {
            if current == targetID { return true }
            if visited.contains(current) { continue }
            visited.insert(current)
            stack.append(contentsOf: dependentIDs(of: current))
        }

        return false
    }

    /// Whether adding `prerequisite ───▶ dependent` would create a cycle.
    ///
    /// Adding the edge creates a cycle if the prerequisite is already reachable from the
    /// dependent (spec §21).
    public func wouldCreateCycle(from prerequisiteID: UUID, to dependentID: UUID) -> Bool {
        isReachable(from: dependentID, to: prerequisiteID)
    }

    /// Validates a proposed `prerequisite ───▶ dependent` dependency, throwing on the first problem.
    public func validateNewDependency(from prerequisiteID: UUID, to dependentID: UUID) throws {
        if prerequisiteID == dependentID {
            throw DependencyValidationError.selfDependency
        }

        let alreadyExists = edges.contains {
            $0.prerequisiteTaskID == prerequisiteID && $0.dependentTaskID == dependentID
        }
        if alreadyExists {
            throw DependencyValidationError.duplicate
        }

        if wouldCreateCycle(from: prerequisiteID, to: dependentID) {
            throw DependencyValidationError.cycle
        }
    }
}
