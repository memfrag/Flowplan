//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftData

/// A Flowplan plan: a directed acyclic graph of tasks connected by dependencies.
@Model
public final class Plan {

    // CloudKit forbids unique constraints, and every stored property must be optional or have a
    // default value — so `id` is a plain UUID (kept unique in practice by generation) with defaults
    // throughout.
    public var id: UUID = UUID()

    public var title: String = ""

    /// An SF Symbol name used as the project's icon.
    public var icon: String = "folder"

    /// A description of what the project is about (project-level metadata).
    public var summary: String = ""

    /// Associated GitHub (or other) repository URLs.
    public var repositoryURLs: [String] = []

    /// The next per-plan task number to hand out. Starts at 1 and only ever increases, so task
    /// numbers are never reused even after tasks are deleted (see ``PlanTask/number``).
    public var nextTaskNumber: Int = 1

    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    // CloudKit requires to-many relationships to be optional. We store them optionally but expose
    // non-optional array accessors so the rest of the app is unaffected (a to-many relationship is a
    // set under the hood, so assigning through the setter dedupes by identity).
    @Relationship(deleteRule: .cascade, inverse: \PlanTask.plan)
    var tasksStorage: [PlanTask]?

    public var tasks: [PlanTask] {
        get { tasksStorage ?? [] }
        set { tasksStorage = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \TaskDependency.plan)
    var dependenciesStorage: [TaskDependency]?

    public var dependencies: [TaskDependency] {
        get { dependenciesStorage ?? [] }
        set { dependenciesStorage = newValue }
    }

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
        self.tasksStorage = tasks
        self.dependenciesStorage = dependencies
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
