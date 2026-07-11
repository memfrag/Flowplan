//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import Flowplan

/// Tests for `PlanStore` mutations and validation, against an in-memory container.
@MainActor
struct PlanStoreTests {

    /// Runs `body` with a freshly built in-memory store, keeping the backing `ModelContainer`
    /// alive for the whole body. `container.mainContext` does *not* retain its container, so a
    /// discarded container would deallocate and invalidate the context mid-test.
    private func withStore(_ body: (PlanStore) throws -> Void) rethrows {
        let container = AppEnvironment.makeModelContainer(inMemory: true)
        let store = PlanStore(modelContext: container.mainContext)
        try withExtendedLifetime(container) {
            try body(store)
        }
    }

    @Test func createTaskAssignsIncrementingNumbers() {
        withStore { store in
            let plan = store.createPlan(title: "P")

            let a = store.createTask(in: plan, title: "A", at: .zero)
            let b = store.createTask(in: plan, title: "B", at: .zero)

            #expect(a.number == 1)
            #expect(b.number == 2)
            #expect(plan.nextTaskNumber == 3)
            #expect(plan.tasks.count == 2)
        }
    }

    @Test func deleteTaskAlsoDeletesReferencingDependencies() throws {
        try withStore { store in
            let plan = store.createPlan(title: "P")
            let a = store.createTask(in: plan, title: "A", at: .zero)
            let b = store.createTask(in: plan, title: "B", at: .zero)
            try store.createDependency(in: plan, from: a, to: b)

            store.deleteTask(a)

            #expect(plan.tasks.count == 1)
            #expect(plan.dependencies.isEmpty)
        }
    }

    @Test func createDependencyRejectsSelfDuplicateAndCycle() throws {
        try withStore { store in
            let plan = store.createPlan(title: "P")
            let a = store.createTask(in: plan, title: "A", at: .zero)
            let b = store.createTask(in: plan, title: "B", at: .zero)

            #expect(throws: DependencyValidationError.selfDependency) {
                try store.createDependency(in: plan, from: a, to: a)
            }

            try store.createDependency(in: plan, from: a, to: b)
            #expect(throws: DependencyValidationError.duplicate) {
                try store.createDependency(in: plan, from: a, to: b)
            }
            // b already depends on a; a -> ... makes a depend on b would cycle.
            #expect(throws: DependencyValidationError.cycle) {
                try store.createDependency(in: plan, from: b, to: a)
            }
        }
    }

    @Test func updateTaskDistinguishesUnchangedFromCleared() {
        withStore { store in
            let plan = store.createPlan(title: "P")
            let task = store.createTask(in: plan, title: "A", at: .zero)
            store.updateTask(task, priority: .some(.high))
            #expect(task.priority == .high)

            // nil = leave unchanged
            store.updateTask(task, title: "Renamed")
            #expect(task.priority == .high)
            #expect(task.title == "Renamed")

            // .some(nil) = clear
            store.updateTask(task, priority: .some(nil))
            #expect(task.priority == nil)
        }
    }

    @Test func commentsAddAndDelete() {
        withStore { store in
            let plan = store.createPlan(title: "P")
            let task = store.createTask(in: plan, title: "A", at: .zero)

            let comment = store.addComment("Found the bug", author: "user", to: task)
            #expect(task.comments.count == 1)

            store.deleteComment(comment)
            #expect(task.comments.isEmpty)
        }
    }

    @Test func deleteClosedTasksRemovesOnlyClosedAndTheirEdges() throws {
        try withStore { store in
            let plan = store.createPlan(title: "P")
            let open = store.createTask(in: plan, title: "Open", at: .zero)
            let closed = store.createTask(in: plan, title: "Closed", at: .zero)
            try store.createDependency(in: plan, from: closed, to: open)
            store.setProgress(.closed, for: closed)

            let removed = store.deleteClosedTasks(in: plan)

            #expect(removed == 1)
            #expect(plan.tasks.map(\.id) == [open.id])
            #expect(plan.dependencies.isEmpty)
        }
    }

    @Test func createPlanAssignsIncreasingSortOrderAndReorderPersists() {
        withStore { store in
            let a = store.createPlan(title: "A")
            let b = store.createPlan(title: "B")
            let c = store.createPlan(title: "C")
            #expect(a.sortOrder == 0 && b.sortOrder == 1 && c.sortOrder == 2)
            #expect(store.allPlans().map(\.title) == ["A", "B", "C"])

            // Move C to the front.
            store.reorderPlans([c, a, b])
            #expect(c.sortOrder == 0 && a.sortOrder == 1 && b.sortOrder == 2)
            #expect(store.allPlans().map(\.title) == ["C", "A", "B"])
        }
    }

    @Test func backfillPlanOrderNumbersLegacyPlansByCreation() {
        withStore { store in
            // Simulate legacy plans that predate the ordering feature: all at the default 0.
            let a = store.createPlan(title: "A")
            let b = store.createPlan(title: "B")
            let c = store.createPlan(title: "C")
            for plan in [a, b, c] { plan.sortOrder = 0 }
            store.save()

            store.backfillPlanOrder()
            #expect(store.allPlans().map(\.title) == ["A", "B", "C"]) // creation order preserved
            #expect(Set([a, b, c].map(\.sortOrder)) == Set([0, 1, 2]))

            // Idempotent + non-destructive: a real order is left alone.
            store.reorderPlans([c, b, a])
            store.backfillPlanOrder()
            #expect(store.allPlans().map(\.title) == ["C", "B", "A"])
        }
    }

    @Test func backfillTaskNumbersIsIdempotent() {
        withStore { store in
            let plan = store.createPlan(title: "P")
            _ = store.createTask(in: plan, title: "A", at: .zero)
            _ = store.createTask(in: plan, title: "B", at: .zero)

            let numbersBefore = plan.tasks.map(\.number).sorted()
            store.backfillTaskNumbers()
            store.backfillTaskNumbers()
            #expect(plan.tasks.map(\.number).sorted() == numbersBefore)
        }
    }
}
