//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftData

/// Builds the sample "Product Launch Plan" used for first launch, development, and previews
/// (spec §19). Tasks are positioned with the layered auto-layout.
@MainActor
public enum SeedData {

    public static func makeSamplePlan() -> Plan {
        let plan = Plan(title: "Product Launch Plan")

        // Tasks in stable order T1…T13. Order matters for deterministic layout.
        let specs: [(key: String, title: String, progress: TaskProgress)] = [
            ("T1", "Define vision", .done),
            ("T2", "Research competitors", .done),
            ("T3", "Set up project", .notStarted),
            ("T4", "Finalize architecture", .done),
            ("T5", "Create wireframes", .notStarted),
            ("T6", "Design onboarding", .inProgress),
            ("T7", "Add dependency rules", .notStarted),
            ("T8", "Build task graph UI", .inProgress),
            ("T9", "Implement sync engine", .inProgress),
            ("T10", "User testing", .notStarted),
            ("T11", "Polish interactions", .notStarted),
            ("T12", "Beta release", .notStarted),
            ("T13", "Launch v1", .notStarted)
        ]

        var taskByKey: [String: PlanTask] = [:]
        let baseDate = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01T12:00:00Z
        var tasks: [PlanTask] = []
        for (index, spec) in specs.enumerated() {
            let task = PlanTask(
                number: index + 1,
                title: spec.title,
                progress: spec.progress,
                createdAt: baseDate.addingTimeInterval(Double(index)),
                updatedAt: baseDate.addingTimeInterval(Double(index))
            )
            taskByKey[spec.key] = task
            tasks.append(task)
        }
        plan.tasks = tasks
        plan.nextTaskNumber = specs.count + 1

        let edges: [(String, String)] = [
            ("T1", "T2"), ("T1", "T3"), ("T2", "T3"), ("T2", "T4"),
            ("T3", "T5"), ("T3", "T6"), ("T3", "T7"),
            ("T5", "T8"), ("T6", "T8"), ("T6", "T9"),
            ("T7", "T10"), ("T4", "T10"),
            ("T8", "T11"), ("T9", "T11"), ("T10", "T11"),
            ("T10", "T12"), ("T11", "T12"), ("T12", "T13")
        ]
        plan.dependencies = edges.compactMap { (from, to) in
            guard let prerequisite = taskByKey[from], let dependent = taskByKey[to] else { return nil }
            return TaskDependency(
                prerequisiteTaskID: prerequisite.id,
                dependentTaskID: dependent.id
            )
        }

        plan.applyAutoLayout()
        return plan
    }
}

// MARK: - Auto-layout helper

extension Plan {

    /// Repositions every task using the layered topological auto-layout (spec §9.2).
    public func applyAutoLayout(metrics: GraphLayoutMetrics = GraphLayoutMetrics()) {
        let orderedTasks = tasks.sorted { $0.createdAt < $1.createdAt }
        let positions = graph.layeredPositions(
            orderedTaskIDs: orderedTasks.map(\.id),
            metrics: metrics
        )
        for task in tasks {
            if let position = positions[task.id] {
                task.position = position
            }
        }
        touch()
    }
}
