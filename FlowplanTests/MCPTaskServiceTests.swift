//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
import SwiftData
@testable import Flowplan

/// Tests for the MCP service layer: addressing, the blocked-state guard, and dependency wiring.
@MainActor
struct MCPTaskServiceTests {

    /// Runs `body` with a fresh in-memory store + service, keeping the backing `ModelContainer`
    /// alive for the whole body (`container.mainContext` does not retain its container).
    private func withService(_ body: (PlanStore, MCPTaskService) throws -> Void) rethrows {
        let container = AppEnvironment.makeModelContainer(inMemory: true)
        let store = PlanStore(modelContext: container.mainContext)
        let service = MCPTaskService(planStore: store)
        try withExtendedLifetime(container) {
            try body(store, service)
        }
    }

    @Test func resolvesProjectByTitleAndReportsNotFound() throws {
        try withService { store, service in
            let plan = store.createPlan(title: "Product Launch")
            _ = store.createTask(in: plan, title: "A", at: .zero)

            let exactCount = try service.listTasks(project: "Product Launch", state: nil).count
            #expect(exactCount == 1)
            // Case-insensitive unique prefix also resolves.
            let prefixCount = try service.listTasks(project: "product", state: nil).count
            #expect(prefixCount == 1)
            #expect(throws: MCPToolError.self) {
                _ = try service.listTasks(project: "Nonexistent", state: nil)
            }
        }
    }

    @Test func ambiguousProjectPrefixThrows() {
        withService { store, service in
            _ = store.createPlan(title: "Alpha One")
            _ = store.createPlan(title: "Alpha Two")
            #expect(throws: MCPToolError.self) {
                _ = try service.listTasks(project: "Alpha", state: nil)
            }
        }
    }

    @Test func resolvesTaskByNumberAndReportsNotFound() throws {
        try withService { store, service in
            let plan = store.createPlan(title: "P")
            _ = store.createTask(in: plan, title: "First", at: .zero)

            let snapshot = try service.getTask(project: "P", task: "1")
            #expect(snapshot.title == "First")
            #expect(throws: MCPToolError.self) {
                _ = try service.getTask(project: "P", task: "999")
            }
        }
    }

    @Test func createTaskWiresPrerequisitesAndDerivesBlocked() throws {
        try withService { store, service in
            let plan = store.createPlan(title: "P")
            _ = store.createTask(in: plan, title: "Prereq", at: .zero) // #1

            let created = try service.createTask(
                project: "P", title: "Dependent", details: nil, notes: nil,
                category: nil, tags: nil, priority: nil, estimateValue: nil,
                estimateUnit: nil, dueDate: nil, prerequisites: ["1"]
            )

            #expect(created.state == "blocked")
            #expect(created.blockedBy.contains { $0.number == 1 })
        }
    }

    @Test func setTaskStateBlockedGuardRejectsUnlessForced() throws {
        try withService { store, service in
            let plan = store.createPlan(title: "P")
            let a = store.createTask(in: plan, title: "A", at: .zero) // #1
            let b = store.createTask(in: plan, title: "B", at: .zero) // #2
            try store.createDependency(in: plan, from: a, to: b)       // B blocked by A

            #expect(throws: MCPToolError.self) {
                _ = try service.setTaskState(project: "P", task: "2", state: "in_progress", force: false)
            }
            // Forced override succeeds.
            let forced = try service.setTaskState(project: "P", task: "2", state: "in_progress", force: true)
            #expect(forced.progress == "in_progress")
        }
    }

    @Test func dueDateParsingAndBadDate() throws {
        try withService { store, service in
            _ = store.createPlan(title: "P").tasks
            _ = store.createTask(in: store.allPlans()[0], title: "A", at: .zero)

            let updated = try service.updateTask(
                project: "P", task: "1", title: nil, details: nil, notes: nil,
                category: nil, tags: nil, priority: nil, estimateValue: nil,
                estimateUnit: nil, dueDate: "2020-01-15"
            )
            #expect(updated.dueDate != nil)
            #expect(updated.overdue == true) // 2020 is in the past

            #expect(throws: MCPToolError.self) {
                _ = try service.updateTask(
                    project: "P", task: "1", title: nil, details: nil, notes: nil,
                    category: nil, tags: nil, priority: nil, estimateValue: nil,
                    estimateUnit: nil, dueDate: "not a date"
                )
            }
        }
    }

    @Test func deleteClosedTasksReportsCount() throws {
        try withService { store, service in
            let plan = store.createPlan(title: "P")
            let closed = store.createTask(in: plan, title: "Closed", at: .zero)
            _ = store.createTask(in: plan, title: "Open", at: .zero)
            store.setProgress(.closed, for: closed)

            let message = try service.deleteClosedTasks(project: "P")
            #expect(message.contains("1"))
            #expect(plan.tasks.count == 1)
        }
    }
}
