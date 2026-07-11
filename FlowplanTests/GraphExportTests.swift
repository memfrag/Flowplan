//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
import Foundation
@testable import Flowplan

/// Tests for the Mermaid and Graphviz (DOT) graph exporters.
@MainActor
struct GraphExportTests {

    private func makePlan() -> Plan {
        let a = PlanTask(number: 1, title: "Define \"vision\"", progress: .done,
                         createdAt: Date(timeIntervalSince1970: 100))
        let b = PlanTask(number: 2, title: "Research", progress: .notStarted,
                         createdAt: Date(timeIntervalSince1970: 200))
        let dependency = TaskDependency(prerequisiteTaskID: a.id, dependentTaskID: b.id)
        return Plan(title: "Test Plan", tasks: [a, b], dependencies: [dependency])
    }

    @Test func mermaidHasNodesEdgesAndClasses() {
        let mermaid = PlanDTO(plan: makePlan()).mermaidGraph()

        #expect(mermaid.hasPrefix("flowchart LR"))
        // Double quotes in a title are swapped for single quotes inside the label.
        #expect(mermaid.contains("n0[\"#1 Define 'vision'\"]"))
        #expect(mermaid.contains("n1[\"#2 Research\"]"))
        #expect(mermaid.contains("n0 --> n1"))
        #expect(mermaid.contains("class n0 done;"))
        #expect(mermaid.contains("class n1 ready;")) // B is ready — its prerequisite A is done
    }

    @Test func dotHasDigraphAndEdges() {
        let dot = PlanDTO(plan: makePlan()).dotGraph()

        #expect(dot.hasPrefix("digraph"))
        #expect(dot.contains("rankdir=LR;"))
        #expect(dot.contains("n0 -> n1;"))
        // Double quotes are backslash-escaped for DOT.
        #expect(dot.contains("#1 Define \\\"vision\\\""))
    }
}
