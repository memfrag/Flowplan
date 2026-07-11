//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
@testable import Flowplan

/// Tests for the Critical Path Method engine (``TaskGraph/criticalPath(durations:)``).
struct CriticalPathTests {

    private func makeGraph(taskIDs: [UUID], edges: [(UUID, UUID)]) -> TaskGraph {
        TaskGraph(
            progressByTask: Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, TaskProgress.notStarted) }),
            edges: edges.map { DependencyEdge(prerequisiteTaskID: $0.0, dependentTaskID: $0.1) }
        )
    }

    /// A diamond A→B→D / A→C→D where the C branch is longer. The critical path is A, C, D and B has slack.
    @Test func diamondPicksLongerBranch() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let graph = makeGraph(taskIDs: [a, b, c, d], edges: [(a, b), (a, c), (b, d), (c, d)])
        let durations: [UUID: Double] = [a: 2, b: 3, c: 5, d: 1]

        let result = graph.criticalPath(durations: durations)

        #expect(result.totalDuration == 8)
        #expect(result.criticalTaskIDs == [a, c, d])
        #expect(result.orderedPath == [a, c, d])
        #expect(result.slackByTask[b] == 2)
        #expect(result.slackByTask[c] == 0)
    }

    /// With equal durations, the critical path is the longest chain by task count.
    @Test func equalDurationsPickLongestChain() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        // a → b → c (chain of 3), plus a standalone d.
        let graph = makeGraph(taskIDs: [a, b, c, d], edges: [(a, b), (b, c)])
        let durations: [UUID: Double] = [a: 1, b: 1, c: 1, d: 1]

        let result = graph.criticalPath(durations: durations)

        #expect(result.totalDuration == 3)
        #expect(result.orderedPath == [a, b, c])
        #expect(!result.criticalTaskIDs.contains(d))
    }

    @Test func emptyGraphIsEmpty() {
        let result = TaskGraph(progressByTask: [:], edges: []).criticalPath(durations: [:])
        #expect(result.isEmpty)
        #expect(result.totalDuration == 0)
    }
}
