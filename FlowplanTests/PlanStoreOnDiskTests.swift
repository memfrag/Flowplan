//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import Flowplan

/// `PlanStore` relationship tests against an **on-disk** store.
///
/// Distinct from `PlanStoreTests`, which uses an in-memory container: only a store that has been
/// closed and reopened comes back with its to-many relationships as unfulfilled faults, which is
/// the state the first write to an empty plan has to cope with.
@MainActor
struct PlanStoreOnDiskTests {

    private let schema = Schema([Plan.self, PlanTask.self, TaskDependency.self, TaskComment.self])

    /// Runs `body` twice against one on-disk store: once to populate it, then again after a full
    /// close/reopen so the fetched objects are faults rather than freshly built instances.
    private func withReopenedStore(
        populate: (PlanStore) throws -> UUID,
        then body: (PlanStore, Plan) throws -> Void
    ) throws {
        let directory = URL.temporaryDirectory.appending(path: "PlanStoreOnDisk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appending(path: "store.sqlite"),
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(for: schema, configurations: [configuration])
        let planID = try withExtendedLifetime(container) {
            try populate(PlanStore(modelContext: container.mainContext))
        }

        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        try withExtendedLifetime(reopened) {
            let descriptor = FetchDescriptor<Plan>(predicate: #Predicate { $0.id == planID })
            let plan = try #require(try reopened.mainContext.fetch(descriptor).first)
            try body(PlanStore(modelContext: reopened.mainContext), plan)
        }
    }

    /// `createTask` writes only the to-one side and lets SwiftData maintain the inverse; this pins
    /// that the inverse really is maintained when the plan's task set starts out as a fault.
    @Test func createsFirstTaskOnEmptyPlanLoadedFromDisk() throws {
        try withReopenedStore { store in
            let plan = store.createPlan(title: "Empty")
            store.save()
            return plan.id
        } then: { store, plan in
            #expect(plan.tasks.isEmpty)

            let task = try #require(store.createTask(in: plan, title: "First", at: .zero))

            #expect(plan.tasks.count == 1)
            #expect(task.plan?.id == plan.id)
        }
    }

    /// A project deleted underneath the UI (the shape a CloudKit-imported deletion takes) must be
    /// reported as not live, so callers refuse to write through the dangling reference rather than
    /// letting CoreData abort the process trying to fault in a row that is gone.
    @Test func deletedPlanIsReportedNotLive() throws {
        try withReopenedStore { store in
            let plan = store.createPlan(title: "Doomed")
            store.save()
            return plan.id
        } then: { store, plan in
            #expect(store.isLive(plan))

            store.deletePlan(plan)

            #expect(!store.isLive(plan))
        }
    }

    /// The same single-sided write for dependencies and comments.
    @Test func createsFirstDependencyAndCommentOnPlanLoadedFromDisk() throws {
        try withReopenedStore { store in
            let plan = store.createPlan(title: "P")
            store.createTask(in: plan, title: "A", at: .zero)
            store.createTask(in: plan, title: "B", at: .zero)
            store.save()
            return plan.id
        } then: { store, plan in
            let a = try #require(plan.tasks.first { $0.title == "A" })
            let b = try #require(plan.tasks.first { $0.title == "B" })

            try store.createDependency(in: plan, from: a, to: b)
            store.addComment("First comment", author: "user", to: a)

            #expect(plan.dependencies.count == 1)
            #expect(a.comments.count == 1)
            #expect(a.comments.first?.task?.id == a.id)
        }
    }
}
