//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
@testable import Flowplan

/// Tests for the pure graph engine, covering the acceptance criteria in spec §25.
struct GraphEngineTests {

    // Helper: build a graph from (id, progress) pairs and (prerequisite, dependent) edges.
    private func makeGraph(
        tasks: [(UUID, TaskProgress)],
        edges: [(UUID, UUID)]
    ) -> TaskGraph {
        TaskGraph(
            progressByTask: Dictionary(uniqueKeysWithValues: tasks),
            edges: edges.map { DependencyEdge(prerequisiteTaskID: $0.0, dependentTaskID: $0.1) }
        )
    }

    // §25.1 — Backlog derivation.
    @Test func backlogDerivation() {
        let a = UUID(), b = UUID()
        let graph = makeGraph(tasks: [(a, .inProgress), (b, .notStarted)], edges: [(a, b)])

        #expect(graph.displayState(of: b) == .backlog)
        #expect(graph.blockerIDs(of: b) == [a])
        #expect(graph.isReadyToStart(b) == false)
    }

    // §25.2 — Ready derivation.
    @Test func readyDerivation() {
        let a = UUID(), b = UUID()
        let graph = makeGraph(tasks: [(a, .done), (b, .notStarted)], edges: [(a, b)])

        #expect(graph.displayState(of: b) == .readyToStart)
        #expect(graph.isReadyToStart(b))
    }

    // A task with no prerequisites is Ready when not started.
    @Test func noDependenciesIsReady() {
        let a = UUID()
        let graph = makeGraph(tasks: [(a, .notStarted)], edges: [])
        #expect(graph.displayState(of: a) == .readyToStart)
    }

    // §25.3 — Unlocking on completion.
    @Test func unlockingOnCompletion() {
        let a = UUID(), b = UUID(), c = UUID()
        // C depends on A and B. A done, B in progress -> C backlog.
        let graph = makeGraph(
            tasks: [(a, .done), (b, .inProgress), (c, .notStarted)],
            edges: [(a, c), (b, c)]
        )
        #expect(graph.displayState(of: c) == .backlog)
        // Completing B should unlock C.
        #expect(graph.unlockedByCompleting(b) == [c])

        // After B is done, C becomes ready.
        let graph2 = makeGraph(
            tasks: [(a, .done), (b, .done), (c, .notStarted)],
            edges: [(a, c), (b, c)]
        )
        #expect(graph2.displayState(of: c) == .readyToStart)
    }

    // §25.4 — Cycle prevention. A -> B -> C, then C -> A is rejected.
    @Test func cyclePrevention() {
        let a = UUID(), b = UUID(), c = UUID()
        let graph = makeGraph(
            tasks: [(a, .notStarted), (b, .notStarted), (c, .notStarted)],
            edges: [(a, b), (b, c)]
        )
        #expect(graph.wouldCreateCycle(from: c, to: a))
        #expect(throws: DependencyValidationError.cycle) {
            try graph.validateNewDependency(from: c, to: a)
        }
        // A valid new edge does not throw.
        #expect(throws: Never.self) {
            try graph.validateNewDependency(from: a, to: c)
        }
    }

    @Test func selfAndDuplicateValidation() {
        let a = UUID(), b = UUID()
        let graph = makeGraph(tasks: [(a, .notStarted), (b, .notStarted)], edges: [(a, b)])

        #expect(throws: DependencyValidationError.selfDependency) {
            try graph.validateNewDependency(from: a, to: a)
        }
        #expect(throws: DependencyValidationError.duplicate) {
            try graph.validateNewDependency(from: a, to: b)
        }
    }

    @Test func layeredLayoutAssignsColumns() {
        let a = UUID(), b = UUID(), c = UUID()
        let graph = makeGraph(
            tasks: [(a, .notStarted), (b, .notStarted), (c, .notStarted)],
            edges: [(a, b), (b, c)]
        )
        let positions = graph.layeredPositions(orderedTaskIDs: [a, b, c])
        #expect(positions[a]!.x < positions[b]!.x)
        #expect(positions[b]!.x < positions[c]!.x)
    }
}

/// Tests for `.flowplan` JSON round-tripping (spec §17.2).
struct CodableTests {

    @Test func planDTORoundTrip() throws {
        let taskID = UUID()
        let depPrereq = UUID()
        let dto = PlanDTO(
            id: UUID(),
            title: "Launch",
            createdAt: Date(timeIntervalSince1970: 1_767_268_800),
            updatedAt: Date(timeIntervalSince1970: 1_767_268_800),
            tasks: [
                TaskDTO(
                    id: taskID, title: "Define vision", notes: "", progress: .done,
                    category: "Planning", tags: ["important"], priority: .high,
                    estimate: TaskEstimate(value: 1, unit: .days),
                    position: PointDTO(x: 100, y: 120),
                    createdAt: Date(timeIntervalSince1970: 1_767_268_800),
                    updatedAt: Date(timeIntervalSince1970: 1_767_268_800)
                )
            ],
            dependencies: [
                DependencyDTO(id: UUID(), prerequisiteTaskID: depPrereq, dependentTaskID: taskID)
            ]
        )

        let data = try dto.jsonData()
        let decoded = try PlanDTO(jsonData: data)

        #expect(decoded.title == "Launch")
        #expect(decoded.tasks.count == 1)
        #expect(decoded.tasks[0].progress == .done)
        #expect(decoded.tasks[0].priority == .high)
        #expect(decoded.tasks[0].estimate == TaskEstimate(value: 1, unit: .days))
        #expect(decoded.dependencies.count == 1)
    }

    @Test func markdownGroupsByState() {
        let a = UUID(), b = UUID()
        let now = Date(timeIntervalSince1970: 1_767_268_800)
        let dto = PlanDTO(
            id: UUID(), title: "Plan", createdAt: now, updatedAt: now,
            tasks: [
                TaskDTO(id: a, title: "Done task", notes: "", progress: .done, category: nil, tags: [], priority: nil, estimate: nil, position: nil, createdAt: now, updatedAt: now),
                TaskDTO(id: b, title: "Blocked task", notes: "", progress: .notStarted, category: nil, tags: [], priority: nil, estimate: nil, position: nil, createdAt: now, updatedAt: now)
            ],
            dependencies: []
        )
        let markdown = dto.markdownSummary()
        #expect(markdown.contains("# Plan"))
        #expect(markdown.contains("## Done"))
        #expect(markdown.contains("Done task"))
    }
}

/// Tests for the seeded sample plan (spec §19).
@MainActor
struct SeedDataTests {

    @Test func sampleDerivedStates() {
        let plan = SeedData.makeSamplePlan()
        let graph = plan.graph

        func task(_ title: String) -> PlanTask { plan.tasks.first { $0.title == title }! }

        // Known Done tasks.
        #expect(graph.displayState(of: task("Define vision").id) == .done)
        #expect(graph.displayState(of: task("Research competitors").id) == .done)
        #expect(graph.displayState(of: task("Finalize architecture").id) == .done)

        // "Set up project" depends on Define vision (done) and Research competitors (done) -> Ready.
        #expect(graph.displayState(of: task("Set up project").id) == .readyToStart)

        // "Beta release" has unfinished prerequisites -> Backlog.
        #expect(graph.displayState(of: task("Beta release").id) == .backlog)

        // Every task has a position assigned by auto-layout.
        #expect(plan.tasks.allSatisfy { $0.position != nil })
    }
}
