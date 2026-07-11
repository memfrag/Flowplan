//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics
import SwiftData

/// A single task in a ``Plan``.
///
/// The stored ``progress`` is simple and manual. The user-facing ``TaskDisplayState`` is derived
/// from this value plus the task's dependencies by the graph engine — it is never stored here.
@Model
public final class PlanTask {

    // CloudKit-compatible: no unique constraint, every property optional or defaulted (see ``Plan``).
    public var id: UUID = UUID()

    /// A stable, per-plan display number (see ``Plan/nextTaskNumber``). Assigned once when the task
    /// is created and never reused or changed — unlike ``id`` it is human-friendly (1, 2, 3, …) and
    /// scoped to the owning plan. `0` means "not yet assigned" (backfilled on load).
    public var number: Int = 0

    public var title: String = ""

    /// A description of what the task entails (distinct from freeform ``notes``).
    public var details: String = ""

    public var notes: String = ""

    /// Backing storage for ``progress``. Stored as a raw string for SwiftData compatibility.
    public var progressRaw: String = TaskProgress.notStarted.rawValue

    public var category: String?
    public var tags: [String] = []

    /// Backing storage for ``priority``.
    public var priorityRaw: String?

    /// Backing storage for ``estimate``.
    public var estimateValue: Double?
    public var estimateUnitRaw: String?

    /// Canvas position. `nil` until laid out (manually or via auto-layout).
    public var positionX: Double?
    public var positionY: Double?

    /// An optional deadline for the task, used by the timeline view and overdue indicators.
    public var dueDate: Date?

    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    /// Identifies the external system this task was imported from, e.g. `"github"`. `nil` for tasks
    /// created inside Flowplan. Enables idempotent re-import (match by ``externalSource`` +
    /// ``externalID``) and a "back to source" link.
    public var externalSource: String?

    /// A stable identifier within ``externalSource`` — for GitHub, `"owner/repo#number"`, unique
    /// across repositories associated with one plan.
    public var externalID: String?

    /// A canonical web URL for the external item (e.g. the issue's `html_url`).
    public var externalURL: String?

    /// The plan this task belongs to. Inverse of ``Plan/tasks``.
    public var plan: Plan?

    /// Comments on this task, e.g. investigation findings or resolution notes. Stored optionally
    /// (CloudKit requires it) but exposed as a non-optional array (see ``Plan/tasks``).
    @Relationship(deleteRule: .cascade, inverse: \TaskComment.task)
    var commentsStorage: [TaskComment]?

    public var comments: [TaskComment] {
        get { commentsStorage ?? [] }
        set { commentsStorage = newValue }
    }

    public init(
        id: UUID = UUID(),
        number: Int = 0,
        title: String,
        details: String = "",
        notes: String = "",
        progress: TaskProgress = .notStarted,
        category: String? = nil,
        tags: [String] = [],
        priority: TaskPriority? = nil,
        estimate: TaskEstimate? = nil,
        position: CGPoint? = nil,
        dueDate: Date? = nil,
        externalSource: String? = nil,
        externalID: String? = nil,
        externalURL: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.details = details
        self.notes = notes
        self.progressRaw = progress.rawValue
        self.category = category
        self.tags = tags
        self.priorityRaw = priority?.rawValue
        self.estimateValue = estimate?.value
        self.estimateUnitRaw = estimate?.unit.rawValue
        self.positionX = position.map { Double($0.x) }
        self.positionY = position.map { Double($0.y) }
        self.dueDate = dueDate
        self.externalSource = externalSource
        self.externalID = externalID
        self.externalURL = externalURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.commentsStorage = nil
    }
}

// MARK: - Typed accessors over raw storage

extension PlanTask {

    public var progress: TaskProgress {
        get { TaskProgress(rawValue: progressRaw) ?? .notStarted }
        set { progressRaw = newValue.rawValue }
    }

    public var priority: TaskPriority? {
        get { priorityRaw.flatMap(TaskPriority.init(rawValue:)) }
        set { priorityRaw = newValue?.rawValue }
    }

    public var estimate: TaskEstimate? {
        get {
            guard let estimateValue, let estimateUnitRaw,
                  let unit = EstimateUnit(rawValue: estimateUnitRaw) else { return nil }
            return TaskEstimate(value: estimateValue, unit: unit)
        }
        set {
            estimateValue = newValue?.value
            estimateUnitRaw = newValue?.unit.rawValue
        }
    }

    /// The card's canvas position, or `nil` if not yet placed.
    public var position: CGPoint? {
        get {
            guard let positionX, let positionY else { return nil }
            return CGPoint(x: positionX, y: positionY)
        }
        set {
            positionX = newValue.map { Double($0.x) }
            positionY = newValue.map { Double($0.y) }
        }
    }

    /// Marks the task as modified now. Call after mutating any user-facing field.
    public func touch() {
        updatedAt = .now
    }

    /// Whether the task's due date is in the past and the task isn't yet resolved (Done/Closed).
    public var isOverdue: Bool {
        guard let dueDate, !progress.isResolved else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: .now)
    }
}
