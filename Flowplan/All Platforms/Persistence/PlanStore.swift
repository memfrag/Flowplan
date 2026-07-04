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
        let descriptor = FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Seeds the sample plan if the store is empty. Safe to call on every launch.
    public func seedIfEmpty() {
        guard allPlans().isEmpty else { return }
        let plan = SeedData.makeSamplePlan()
        modelContext.insert(plan)
        save()
    }

    @discardableResult
    public func createPlan(title: String = "Untitled Plan") -> Plan {
        let plan = Plan(title: title)
        modelContext.insert(plan)
        save()
        return plan
    }

    public func deletePlan(_ plan: Plan) {
        modelContext.delete(plan)
        save()
    }

    // MARK: - Tasks

    @discardableResult
    public func createTask(in plan: Plan, title: String = "New Task", at position: CGPoint) -> PlanTask {
        let task = PlanTask(title: title, position: position)
        task.plan = plan
        plan.tasks.append(task)
        plan.touch()
        save()
        return task
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

    /// Duplicates a task (without its dependencies), offset slightly so it is visible (spec §14, Cmd+D).
    @discardableResult
    public func duplicateTask(_ task: PlanTask) -> PlanTask {
        let copy = PlanTask(
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
