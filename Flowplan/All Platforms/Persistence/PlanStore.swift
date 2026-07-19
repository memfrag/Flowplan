//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics
import SwiftData
import OSLog

/// The mutation, validation, and seeding layer over a SwiftData `ModelContext`.
///
/// Views read models directly (SwiftData models are observable) and via `@Query`; all *writes*
/// go through this store so validation (no self-dependency, no duplicate, no cycle) and cascade
/// clean-up live in one place.
@Observable @MainActor
public final class PlanStore {

    @ObservationIgnored
    public let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Plans

    public func allPlans() -> [Plan] {
        let descriptor = FetchDescriptor<Plan>(sortBy: Plan.displayOrder)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// The distinct group names in use, alphabetically. Excludes the empty (ungrouped) name.
    public func planGroups() -> [String] {
        Array(Set(allPlans().map(\.group))).filter { !$0.isEmpty }.sorted()
    }

    /// Moves a project into a group (empty name = ungrouped), sending it to the end of that group so
    /// it doesn't wedge itself into the middle based on its previous position.
    public func setGroup(_ group: String, for plan: Plan) {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plan.group != trimmed else { return }
        plan.group = trimmed
        plan.sortOrder = nextPlanSortOrder()
        plan.touch()
        save()
    }

    /// Seeds the sample plan if the store is empty. Safe to call on every launch.
    public func seedIfEmpty() {
        guard allPlans().isEmpty else { return }
        let plan = SeedData.makeSamplePlan()
        modelContext.insert(plan)
        save()
    }

    /// Assigns stable numbers to any tasks that predate the numbering feature (or arrived via import
    /// without one), and reconciles each plan's ``Plan/nextTaskNumber`` so future tasks never collide
    /// with existing ones. Idempotent — safe to call on every launch.
    public func backfillTaskNumbers() {
        var didChange = false
        for plan in allPlans() {
            let unnumbered = plan.tasks.filter { $0.number <= 0 }
            var counter = max(plan.nextTaskNumber, (plan.tasks.map(\.number).max() ?? 0) + 1)
            for task in unnumbered.sorted(by: { $0.createdAt < $1.createdAt }) {
                task.number = counter
                counter += 1
                didChange = true
            }
            if plan.nextTaskNumber < counter {
                plan.nextTaskNumber = counter
                didChange = true
            }
        }
        if didChange { save() }
    }

    @discardableResult
    public func createPlan(title: String = "Untitled Plan") -> Plan {
        let plan = Plan(title: title)
        plan.sortOrder = nextPlanSortOrder()
        modelContext.insert(plan)
        save()
        return plan
    }

    /// The sort index for a new project: one past the current maximum, so it lands at the end.
    private func nextPlanSortOrder() -> Int {
        (allPlans().map(\.sortOrder).max() ?? -1) + 1
    }

    /// Persists a new project ordering by assigning sequential sort indices in the given order.
    /// Used by the Project Manager's drag-to-reorder.
    public func reorderPlans(_ orderedPlans: [Plan]) {
        for (index, plan) in orderedPlans.enumerated() where plan.sortOrder != index {
            plan.sortOrder = index
            plan.touch()
        }
        save()
    }

    /// Assigns sequential sort orders to projects that predate the ordering feature (all at 0),
    /// using creation order so the initial ordering matches what users saw before. Idempotent.
    public func backfillPlanOrder() {
        let ordered = allPlans().sorted { $0.createdAt < $1.createdAt }
        // Only backfill when the stored order is degenerate (everything still at the default 0);
        // otherwise a user-defined order is already in place and must be preserved.
        let distinctOrders = Set(ordered.map(\.sortOrder))
        guard ordered.count > 1, distinctOrders.count <= 1 else { return }
        for (index, plan) in ordered.enumerated() where plan.sortOrder != index {
            plan.sortOrder = index
        }
        save()
    }

    public func deletePlan(_ plan: Plan) {
        modelContext.delete(plan)
        save()
    }

    // MARK: - Tasks

    @discardableResult
    public func createTask(in plan: Plan, title: String = "New Task", at position: CGPoint) -> PlanTask {
        let task = PlanTask(number: nextTaskNumber(in: plan), title: title, position: position)
        task.plan = plan
        plan.tasks.append(task)
        plan.touch()
        save()
        return task
    }

    /// Claims the plan's next task number, advancing the counter so numbers are never reused.
    private func nextTaskNumber(in plan: Plan) -> Int {
        let number = plan.nextTaskNumber
        plan.nextTaskNumber = number + 1
        return number
    }

    /// Deletes a task and every dependency that references it (spec §10.6).
    public func deleteTask(_ task: PlanTask) {
        guard let plan = task.plan else {
            modelContext.delete(task)
            save()
            return
        }
        let referencing = plan.dependencies.filter {
            $0.prerequisiteTaskID == task.id || $0.dependentTaskID == task.id
        }
        for dependency in referencing {
            modelContext.delete(dependency)
        }
        modelContext.delete(task)
        plan.touch()
        save()
    }

    /// Permanently deletes every Closed task in the plan, along with any dependency edges that
    /// reference them, in a single save. Returns the number of tasks removed.
    @discardableResult
    public func deleteClosedTasks(in plan: Plan) -> Int {
        let closed = plan.tasks.filter { $0.progress == .closed }
        guard !closed.isEmpty else { return 0 }
        let closedIDs = Set(closed.map(\.id))
        let referencing = plan.dependencies.filter {
            closedIDs.contains($0.prerequisiteTaskID) || closedIDs.contains($0.dependentTaskID)
        }
        for dependency in referencing {
            modelContext.delete(dependency)
        }
        for task in closed {
            modelContext.delete(task)
        }
        plan.touch()
        save()
        return closed.count
    }

    /// Duplicates a task (without its dependencies), offset slightly so it is visible (spec §14, Cmd+D).
    @discardableResult
    public func duplicateTask(_ task: PlanTask) -> PlanTask {
        let copy = PlanTask(
            number: task.plan.map(nextTaskNumber(in:)) ?? 0,
            title: task.title + " copy",
            notes: task.notes,
            progress: task.progress,
            category: task.category,
            tags: task.tags,
            priority: task.priority,
            estimate: task.estimate,
            position: (task.position ?? CGPoint(x: 200, y: 200)).applying(.init(translationX: 32, y: 32))
        )
        copy.plan = task.plan
        task.plan?.tasks.append(copy)
        task.plan?.touch()
        save()
        return copy
    }

    public func setProgress(_ progress: TaskProgress, for task: PlanTask) {
        task.progress = progress
        task.touch()
        task.plan?.touch()
        save()
    }

    /// Applies non-nil field updates to a task in one save. Double optionals distinguish
    /// "leave unchanged" (`nil`) from "clear the field" (`.some(nil)`).
    public func updateTask(
        _ task: PlanTask,
        title: String? = nil,
        details: String? = nil,
        notes: String? = nil,
        category: String?? = nil,
        tags: [String]? = nil,
        priority: TaskPriority?? = nil,
        estimate: TaskEstimate?? = nil,
        dueDate: Date?? = nil
    ) {
        if let title { task.title = title }
        if let details { task.details = details }
        if let notes { task.notes = notes }
        if let category { task.category = category }
        if let tags { task.tags = tags }
        if let priority { task.priority = priority }
        if let estimate { task.estimate = estimate }
        if let dueDate { task.dueDate = dueDate }
        task.touch()
        task.plan?.touch()
        save()
    }

    /// Links a task to the external system it was imported from (e.g. GitHub). Used by importers to
    /// stamp identity so re-import can match and update in place rather than duplicate.
    public func setExternalReference(source: String?, id: String?, url: String?, for task: PlanTask) {
        task.externalSource = source
        task.externalID = id
        task.externalURL = url
        task.touch()
        task.plan?.touch()
        save()
    }

    // MARK: - Comments

    @discardableResult
    public func addComment(_ text: String, author: String, to task: PlanTask) -> TaskComment {
        let comment = TaskComment(author: author, text: text)
        comment.task = task
        task.comments.append(comment)
        task.touch()
        task.plan?.touch()
        save()
        return comment
    }

    public func deleteComment(_ comment: TaskComment) {
        let task = comment.task
        modelContext.delete(comment)
        task?.touch()
        task?.plan?.touch()
        save()
    }

    public func updatePosition(_ position: CGPoint, for task: PlanTask) {
        task.position = position
        save()
    }

    // MARK: - Dependencies

    /// Validates and creates a `prerequisite ───▶ dependent` dependency, or throws
    /// ``DependencyValidationError`` (spec §5.3).
    @discardableResult
    public func createDependency(in plan: Plan, from prerequisite: PlanTask, to dependent: PlanTask) throws -> TaskDependency {
        try plan.graph.validateNewDependency(from: prerequisite.id, to: dependent.id)
        let dependency = TaskDependency(prerequisiteTaskID: prerequisite.id, dependentTaskID: dependent.id)
        dependency.plan = plan
        plan.dependencies.append(dependency)
        plan.touch()
        save()
        return dependency
    }

    public func deleteDependency(_ dependency: TaskDependency) {
        let plan = dependency.plan
        modelContext.delete(dependency)
        plan?.touch()
        save()
    }

    // MARK: - Import

    /// Inserts a plan decoded from a `.flowplan` / JSON DTO.
    @discardableResult
    public func importPlan(_ dto: PlanDTO) -> Plan {
        let plan = dto.makePlan()
        // Order is a cross-plan concept, so an imported plan goes to the end rather than trusting
        // an index that would collide with existing projects.
        plan.sortOrder = nextPlanSortOrder()
        modelContext.insert(plan)
        save()
        return plan
    }

    // MARK: - Saving

    public func save() {
        do {
            try modelContext.save()
        } catch {
            Logger.persistence.error("Failed to save model context: \(error.localizedDescription)")
        }
    }
}

extension Logger {
    static let persistence = Logger(subsystem: "io.apparata.Flowplan", category: "Persistence")
}
