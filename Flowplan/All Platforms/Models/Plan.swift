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

    /// An SF Symbol name used as the project's icon.
    public var icon: String = "folder"

    /// A description of what the project is about (project-level metadata).
    public var summary: String = ""

    /// Associated GitHub (or other) repository URLs.
    public var repositoryURLs: [String] = []

    /// The next per-plan task number to hand out. Starts at 1 and only ever increases, so task
    /// numbers are never reused even after tasks are deleted (see ``PlanTask/number``).
    public var nextTaskNumber: Int = 1

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlanTask.plan)
    public var tasks: [PlanTask]

    @Relationship(deleteRule: .cascade, inverse: \TaskDependency.plan)
    public var dependencies: [TaskDependency]

    public init(
        id: UUID = UUID(),
        title: String,
        icon: String = "folder",
        summary: String = "",
        repositoryURLs: [String] = [],
        nextTaskNumber: Int = 1,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tasks: [PlanTask] = [],
        dependencies: [TaskDependency] = []
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.summary = summary
        self.repositoryURLs = repositoryURLs
        self.nextTaskNumber = nextTaskNumber
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
