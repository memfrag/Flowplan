//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
import SwiftData
@testable import Flowplan

/// Tests for the DTO layer: JSON round-trip and backward compatibility with older `.flowplan` files.
@MainActor
struct FlowplanCodableTests {

    /// Runs `body` with a fresh in-memory store, keeping the backing `ModelContainer` alive for
    /// the whole body (`container.mainContext` does not retain its container).
    private func withStore(_ body: (PlanStore) throws -> Void) rethrows {
        let container = AppEnvironment.makeModelContainer(inMemory: true)
        let store = PlanStore(modelContext: container.mainContext)
        try withExtendedLifetime(container) {
            try body(store)
        }
    }

    @Test func roundTripPreservesTasksDependenciesAndMetadata() throws {
        try withStore { store in
            let plan = store.createPlan(title: "Round Trip")
            store.setGroup("Work", for: plan)
            let a = store.createTask(in: plan, title: "A", at: .zero)
            let b = store.createTask(in: plan, title: "B", at: .zero)
            try store.createDependency(in: plan, from: a, to: b)
            store.updateTask(a, dueDate: .some(Date(timeIntervalSince1970: 1_000_000)))
            store.addComment("note", author: "user", to: b)

            let data = try PlanDTO(plan: plan).jsonData()
            let restored = try PlanDTO(jsonData: data).makePlan()

            #expect(restored.title == "Round Trip")
            #expect(restored.group == "Work")
            #expect(restored.tasks.count == 2)
            #expect(restored.dependencies.count == 1)
            #expect(restored.tasks.first { $0.title == "A" }?.dueDate != nil)
            #expect(restored.tasks.first { $0.title == "B" }?.comments.count == 1)
            #expect(Set(restored.tasks.map(\.number)) == [1, 2])
        }
    }

    @Test func decodesOlderFileMissingOptionalFieldsAndBackfillsNumbers() throws {
        // A file written before `number`, `details`, `dueDate`, and `comments` existed.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Old Plan",
          "createdAt": "2024-01-01T00:00:00Z",
          "updatedAt": "2024-01-01T00:00:00Z",
          "tasks": [
            {
              "id": "\(UUID().uuidString)",
              "title": "Legacy Task",
              "notes": "",
              "progress": "notStarted",
              "category": null,
              "tags": [],
              "priority": null,
              "estimate": null,
              "position": null,
              "createdAt": "2024-01-01T00:00:00Z",
              "updatedAt": "2024-01-01T00:00:00Z"
            }
          ],
          "dependencies": []
        }
        """

        let dto = try PlanDTO(jsonData: Data(json.utf8))
        let plan = dto.makePlan()

        #expect(plan.title == "Old Plan")
        #expect(plan.tasks.count == 1)
        let task = plan.tasks[0]
        #expect(task.title == "Legacy Task")
        #expect(task.number == 1)       // backfilled
        #expect(task.details.isEmpty)   // default
        #expect(task.dueDate == nil)    // default
        #expect(task.comments.isEmpty)  // default
    }
}
