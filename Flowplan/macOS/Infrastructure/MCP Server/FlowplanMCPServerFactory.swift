//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import MCP

/// Builds an MCP ``Server`` wired to a ``MCPTaskService``. One server instance is created per HTTP
/// session by ``MCPServerController``.
nonisolated enum FlowplanMCPServerFactory {

    static func makeServer(service: MCPTaskService) async -> Server {
        let server = Server(
            name: "Flowplan",
            version: "1.0.0",
            instructions: """
            Flowplan tracks a project's tasks and their dependencies so you can see what's actionable \
            and record what you learn as you work.

            Addressing: reference a project by its title or UUID, and a task by its stable per-project \
            number (shown in the app as "#N", e.g. "7") or by UUID — numbers are never reused.

            A task's derived state is one of: blocked, ready, in_progress, done, closed. "blocked" means \
            it has unresolved prerequisites; it is derived automatically and cannot be set directly. Use \
            next_ready_tasks to find actionable work. set_task_state refuses to move a blocked task to \
            in_progress or done (listing the blockers) unless force=true.

            Use add_comment to record investigation notes or how a task was resolved — this is visible \
            to the user in the app's task inspector.
            """,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPToolCatalog.tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let text = try await dispatch(params, service: service)
                return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
            } catch let error as MCPToolError {
                return .init(content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
            } catch {
                return .init(content: [.text(text: "Internal error: \(error)", annotations: nil, _meta: nil)], isError: true)
            }
        }

        return server
    }

    // MARK: - Dispatch

    private static func dispatch(_ params: CallTool.Parameters, service: MCPTaskService) async throws -> String {
        let args = params.arguments ?? [:]

        func requireString(_ key: String) throws -> String {
            guard let value = args[key]?.stringValue, !value.isEmpty else {
                throw MCPToolError.invalidArgument("Missing required argument \"\(key)\".")
            }
            return value
        }
        func optionalString(_ key: String) -> String? { args[key]?.stringValue }
        func optionalStringArray(_ key: String) -> [String]? {
            args[key]?.arrayValue?.compactMap(\.stringValue)
        }
        func optionalDouble(_ key: String) -> Double? {
            args[key]?.doubleValue ?? args[key]?.intValue.map(Double.init)
        }
        func optionalBool(_ key: String) -> Bool { args[key]?.boolValue ?? false }

        switch params.name {
        case "list_projects":
            return MCPJSON.string(await service.listProjects())

        case "list_tasks":
            let project = try requireString("project")
            let tasks = try await service.listTasks(project: project, state: optionalString("state"))
            return MCPJSON.string(tasks)

        case "get_task":
            let project = try requireString("project")
            let task = try requireString("task")
            return MCPJSON.string(try await service.getTask(project: project, task: task))

        case "next_ready_tasks":
            let project = try requireString("project")
            return MCPJSON.string(try await service.nextReadyTasks(project: project))

        case "create_task":
            let project = try requireString("project")
            let title = try requireString("title")
            let snapshot = try await service.createTask(
                project: project,
                title: title,
                details: optionalString("details"),
                notes: optionalString("notes"),
                category: optionalString("category"),
                tags: optionalStringArray("tags"),
                priority: optionalString("priority"),
                estimateValue: optionalDouble("estimate_value"),
                estimateUnit: optionalString("estimate_unit"),
                dueDate: optionalString("due_date"),
                prerequisites: optionalStringArray("prerequisites")
            )
            return MCPJSON.string(snapshot)

        case "update_task":
            let project = try requireString("project")
            let task = try requireString("task")
            let snapshot = try await service.updateTask(
                project: project,
                task: task,
                title: optionalString("title"),
                details: optionalString("details"),
                notes: optionalString("notes"),
                category: optionalString("category"),
                tags: optionalStringArray("tags"),
                priority: optionalString("priority"),
                estimateValue: optionalDouble("estimate_value"),
                estimateUnit: optionalString("estimate_unit"),
                dueDate: optionalString("due_date")
            )
            return MCPJSON.string(snapshot)

        case "set_task_state":
            let project = try requireString("project")
            let task = try requireString("task")
            let state = try requireString("state")
            let snapshot = try await service.setTaskState(
                project: project, task: task, state: state, force: optionalBool("force")
            )
            return MCPJSON.string(snapshot)

        case "add_dependency":
            let project = try requireString("project")
            let prerequisite = try requireString("prerequisite")
            let dependent = try requireString("dependent")
            let snapshot = try await service.addDependency(project: project, prerequisite: prerequisite, dependent: dependent)
            return MCPJSON.string(snapshot)

        case "remove_dependency":
            let project = try requireString("project")
            let prerequisite = try requireString("prerequisite")
            let dependent = try requireString("dependent")
            let snapshot = try await service.removeDependency(project: project, prerequisite: prerequisite, dependent: dependent)
            return MCPJSON.string(snapshot)

        case "delete_task":
            let project = try requireString("project")
            let task = try requireString("task")
            return try await service.deleteTask(project: project, task: task)

        case "add_comment":
            let project = try requireString("project")
            let task = try requireString("task")
            let text = try requireString("text")
            let author = optionalString("author") ?? "agent"
            let snapshot = try await service.addComment(project: project, task: task, text: text, author: author)
            return MCPJSON.string(snapshot)

        default:
            throw MCPToolError.invalidArgument("Unknown tool \"\(params.name)\".")
        }
    }
}
