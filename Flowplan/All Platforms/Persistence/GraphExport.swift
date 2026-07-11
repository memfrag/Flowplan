//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

// MARK: - Mermaid / Graphviz graph export (spec §23)

extension PlanDTO {

    /// Renders the dependency graph as a Mermaid `flowchart` (left-to-right), with nodes coloured by
    /// derived display state. Edges read prerequisite → dependent.
    public func mermaidGraph() -> String {
        let graph = makeGraph()
        let nodeIDByTask = nodeIDs()

        var lines: [String] = ["flowchart LR"]
        for (state, className) in Self.mermaidClasses {
            let color = Self.stateHex[state]!
            lines.append("    classDef \(className) fill:\(color.fill),stroke:\(color.stroke),color:#fff;")
        }

        for task in tasks {
            guard let id = nodeIDByTask[task.id] else { continue }
            lines.append("    \(id)[\"\(Self.mermaidLabel(number: task.number, title: task.title))\"]")
            lines.append("    class \(id) \(Self.mermaidClasses[graph.displayState(of: task.id)] ?? "blocked");")
        }

        for dependency in dependencies {
            guard let from = nodeIDByTask[dependency.prerequisiteTaskID],
                  let to = nodeIDByTask[dependency.dependentTaskID] else { continue }
            lines.append("    \(from) --> \(to)")
        }

        return lines.joined(separator: "\n")
    }

    /// Renders the dependency graph as Graphviz DOT (left-to-right), with nodes filled by derived
    /// display state.
    public func dotGraph() -> String {
        let graph = makeGraph()
        let nodeIDByTask = nodeIDs()
        let name = Self.dotEscaped(title.isEmpty ? "Flowplan" : title)

        var lines: [String] = [
            "digraph \"\(name)\" {",
            "    rankdir=LR;",
            "    node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", fontcolor=\"white\"];"
        ]

        for task in tasks {
            guard let id = nodeIDByTask[task.id] else { continue }
            let label = Self.dotEscaped(Self.plainLabel(number: task.number, title: task.title))
            let fill = Self.stateHex[graph.displayState(of: task.id)]!.fill
            lines.append("    \(id) [label=\"\(label)\", fillcolor=\"\(fill)\"];")
        }

        for dependency in dependencies {
            guard let from = nodeIDByTask[dependency.prerequisiteTaskID],
                  let to = nodeIDByTask[dependency.dependentTaskID] else { continue }
            lines.append("    \(from) -> \(to);")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func makeGraph() -> TaskGraph {
        TaskGraph(
            progressByTask: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.progress) }),
            edges: dependencies.map { DependencyEdge(id: $0.id, prerequisiteTaskID: $0.prerequisiteTaskID, dependentTaskID: $0.dependentTaskID) }
        )
    }

    /// Stable, format-safe node ids by task order (`n0`, `n1`, …).
    private func nodeIDs() -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: tasks.enumerated().map { ($0.element.id, "n\($0.offset)") })
    }

    private static func plainLabel(number: Int?, title: String) -> String {
        let name = title.isEmpty ? "Untitled" : title
        if let number, number > 0 { return "#\(number) \(name)" }
        return name
    }

    private static func mermaidLabel(number: Int?, title: String) -> String {
        // Inside a "…" Mermaid label: drop newlines and swap double quotes for single quotes.
        plainLabel(number: number, title: title)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
    }

    private static func dotEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static let mermaidClasses: [TaskDisplayState: String] = [
        .backlog: "blocked",
        .readyToStart: "ready",
        .inProgress: "inProgress",
        .done: "done",
        .closed: "closed"
    ]

    private static let stateHex: [TaskDisplayState: (fill: String, stroke: String)] = [
        .backlog: ("#9e9e9e", "#616161"),
        .readyToStart: ("#2196f3", "#1565c0"),
        .inProgress: ("#ff9800", "#e65100"),
        .done: ("#4caf50", "#2e7d32"),
        .closed: ("#757575", "#424242")
    ]
}
