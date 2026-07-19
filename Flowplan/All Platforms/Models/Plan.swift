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

    /// The name of the group this project belongs to; empty means ungrouped. Groups are ad hoc —
    /// there's no group entity, so a group exists exactly as long as some project names it.
    public var group: String = ""

    /// Manual display order for the project list and sidebar picker; lower comes first. Backfilled
    /// by creation order for projects that predate the feature, and new projects go to the end.
    ///
    /// Indices are global rather than per-group; ``group`` is the primary sort key, so a globally
    /// increasing order still lays out correctly within each group.
    public var sortOrder: Int = 0

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
        group: String = "",
        sortOrder: Int = 0,
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
        self.group = group
        self.sortOrder = sortOrder
        self.nextTaskNumber = nextTaskNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasksStorage = tasks
        self.dependenciesStorage = dependencies
    }
}

// MARK: - Ordering

extension Plan {

    /// The canonical order for every project list: grouped first (the empty, ungrouped name sorts
    /// ahead of all others), then by manual order, then by creation date as a tiebreaker.
    ///
    /// Shared by every `@Query` and fetch so the Project Manager, sidebar picker and command palette
    /// can't drift out of sync.
    public static let displayOrder: [SortDescriptor<Plan>] = [
        SortDescriptor(\.group),
        SortDescriptor(\.sortOrder),
        SortDescriptor(\.createdAt)
    ]
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
