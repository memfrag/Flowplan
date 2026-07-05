//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Errors surfaced to an MCP client as a tool-call failure (`isError: true` with a text message).
nonisolated enum MCPToolError: Error, Sendable {
    case projectNotFound(query: String, available: [String])
    case ambiguousProject(query: String, matches: [String])
    case taskNotFound(project: String, query: String)
    case invalidArgument(String)
    case taskBlocked(task: String, blockers: [String])
    case dependencyInvalid(DependencyValidationError)
    case dependencyNotFound

    var message: String {
        switch self {
        case .projectNotFound(let query, let available):
            let list = available.isEmpty ? "There are no projects yet." : "Available projects: \(available.joined(separator: ", "))."
            return "No project matches \"\(query)\". \(list)"
        case .ambiguousProject(let query, let matches):
            return "\"\(query)\" matches multiple projects: \(matches.joined(separator: ", ")). Use the full title or the project's UUID."
        case .taskNotFound(let project, let query):
            return "No task matching \"\(query)\" was found in project \"\(project)\"."
        case .invalidArgument(let detail):
            return detail
        case .taskBlocked(let task, let blockers):
            let list = blockers.joined(separator: ", ")
            return "Task \(task) is blocked by unfinished prerequisites: \(list). Finish those first, or pass force=true to override."
        case .dependencyInvalid(let error):
            return "\(error.title) \(error.message)"
        case .dependencyNotFound:
            return "That dependency does not exist."
        }
    }
}
