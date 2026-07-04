//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

// MARK: - Markdown summary export (spec §18.2)

extension PlanDTO {

    /// Renders a Markdown summary of the plan, grouping tasks by derived display state.
    public func markdownSummary() -> String {
        let graph = TaskGraph(
            progressByTask: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.progress) }),
            edges: dependencies.map { DependencyEdge(id: $0.id, prerequisiteTaskID: $0.prerequisiteTaskID, dependentTaskID: $0.dependentTaskID) }
        )

        let titlesByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })

        func tasksMatching(_ state: TaskDisplayState) -> [TaskDTO] {
            tasks.filter { graph.displayState(of: $0.id) == state }
        }

        var lines: [String] = ["# \(title)", ""]

        func appendSection(_ heading: String, state: TaskDisplayState, includeBlockers: Bool = false) {
            let matching = tasksMatching(state)
            guard !matching.isEmpty else { return }
            lines.append("## \(heading)")
            lines.append("")
            for task in matching {
                lines.append("- \(task.title)")
                if includeBlockers {
                    let blockers = graph.blockerIDs(of: task.id).compactMap { titlesByID[$0] }
                    if !blockers.isEmpty {
                        lines.append("  - Blocked by: \(blockers.joined(separator: ", "))")
                    }
                }
            }
            lines.append("")
        }

        appendSection("Ready to Start", state: .readyToStart)
        appendSection("In Progress", state: .inProgress)
        appendSection("Backlog", state: .backlog, includeBlockers: true)
        appendSection("Done", state: .done)

        return lines.joined(separator: "\n")
    }
}
