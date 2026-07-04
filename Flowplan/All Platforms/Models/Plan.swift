//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftData

/// A Flowplan plan: a directed acyclic graph of tasks connected by dependencies.
@Model
public final class Plan {

    @Attribute(.unique) public var id: UUID

    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlanTask.plan)
    public var tasks: [PlanTask]

    @Relationship(deleteRule: .cascade, inverse: \TaskDependency.plan)
    public var dependencies: [TaskDependency]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tasks: [PlanTask] = [],
        dependencies: [TaskDependency] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasks = tasks
        self.dependencies = dependencies
    }
}

// MARK: - Convenience

extension Plan {

    /// Looks up a task by id.
    public func task(id: UUID) -> PlanTask? {
        tasks.first { $0.id == id }
    }

    /// A graph snapshot suitable for the pure graph engine and its queries.
    public var graph: TaskGraph {
        TaskGraph(
            progressByTask: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.progress) }),
            edges: dependencies.map(\.edge)
        )
    }

    public func touch() {
        updatedAt = .now
    }
}
