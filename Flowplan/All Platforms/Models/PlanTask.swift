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

    @Attribute(.unique) public var id: UUID

    public var title: String
    public var notes: String

    /// Backing storage for ``progress``. Stored as a raw string for SwiftData compatibility.
    public var progressRaw: String

    public var category: String?
    public var tags: [String]

    /// Backing storage for ``priority``.
    public var priorityRaw: String?

    /// Backing storage for ``estimate``.
    public var estimateValue: Double?
    public var estimateUnitRaw: String?

    /// Canvas position. `nil` until laid out (manually or via auto-layout).
    public var positionX: Double?
    public var positionY: Double?

    public var createdAt: Date
    public var updatedAt: Date

    /// The plan this task belongs to. Inverse of ``Plan/tasks``.
    public var plan: Plan?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        progress: TaskProgress = .notStarted,
        category: String? = nil,
        tags: [String] = [],
        priority: TaskPriority? = nil,
        estimate: TaskEstimate? = nil,
        position: CGPoint? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.progressRaw = progress.rawValue
        self.category = category
        self.tags = tags
        self.priorityRaw = priority?.rawValue
        self.estimateValue = estimate?.value
        self.estimateUnitRaw = estimate?.unit.rawValue
        self.positionX = position.map { Double($0.x) }
        self.positionY = position.map { Double($0.y) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
}
