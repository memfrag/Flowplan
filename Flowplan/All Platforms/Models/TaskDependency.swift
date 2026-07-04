//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftData

/// A directed dependency edge between two tasks in a ``Plan``.
///
/// The relationship reads: `prerequisiteTaskID ───▶ dependentTaskID`, meaning the prerequisite
/// task must be Done before the dependent task can become Ready to Start.
///
/// Task identifiers are stored as raw `UUID`s (rather than SwiftData relationships) so the graph
/// algorithms can operate on plain values without touching the persistence layer.
@Model
public final class TaskDependency {

    @Attribute(.unique) public var id: UUID

    /// The task that must be completed first.
    public var prerequisiteTaskID: UUID

    /// The task that depends on the prerequisite.
    public var dependentTaskID: UUID

    /// The plan this dependency belongs to. Inverse of ``Plan/dependencies``.
    public var plan: Plan?

    public init(
        id: UUID = UUID(),
        prerequisiteTaskID: UUID,
        dependentTaskID: UUID
    ) {
        self.id = id
        self.prerequisiteTaskID = prerequisiteTaskID
        self.dependentTaskID = dependentTaskID
    }

    /// A lightweight, `Sendable` value representation for use by the graph engine.
    public var edge: DependencyEdge {
        DependencyEdge(id: id, prerequisiteTaskID: prerequisiteTaskID, dependentTaskID: dependentTaskID)
    }
}

/// A plain-value dependency edge, decoupled from SwiftData, for graph computations and tests.
nonisolated public struct DependencyEdge: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var prerequisiteTaskID: UUID
    public var dependentTaskID: UUID

    public init(id: UUID = UUID(), prerequisiteTaskID: UUID, dependentTaskID: UUID) {
        self.id = id
        self.prerequisiteTaskID = prerequisiteTaskID
        self.dependentTaskID = dependentTaskID
    }
}
