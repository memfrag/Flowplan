//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import MCP

/// The MCP tool definitions Flowplan exposes. Task references accept a project's stable per-task
/// number (as shown in the app, e.g. `"7"`) or a UUID; project references accept a title or UUID.
nonisolated enum MCPToolCatalog {

    static let tools: [Tool] = [
        Tool(
            name: "list_projects",
            description: "List every Flowplan project with a task-count breakdown by state (blocked, ready, in_progress, done, closed).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:])
            ])
        ),
        Tool(
            name: "list_tasks",
            description: "List a project's tasks, optionally filtered by derived state.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "state": [
                        "type": "string",
                        "description": "Filter by derived state",
                        "enum": ["blocked", "ready", "in_progress", "done", "closed"]
                    ]
                ],
                "required": ["project"]
            ])
        ),
        Tool(
            name: "get_task",
            description: "Get full details for a task, including its derived state, blockers, prerequisites, dependents, and comments.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "task": ["type": "string", "description": "Task number (e.g. \"7\") or UUID"]
                ],
                "required": ["project", "task"]
            ])
        ),
        Tool(
            name: "next_ready_tasks",
            description: "List tasks that are Ready to Start (all prerequisites resolved), sorted by priority. Use this to find actionable work.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"]
                ],
                "required": ["project"]
            ])
        ),
        Tool(
            name: "create_task",
            description: "Create a new task in a project. Optionally wire it to prerequisites by task reference.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "title": ["type": "string"],
                    "details": ["type": "string", "description": "What the task entails"],
                    "notes": ["type": "string"],
                    "category": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "priority": ["type": "string", "enum": ["low", "medium", "high"]],
                    "estimate_value": ["type": "number"],
                    "estimate_unit": ["type": "string", "enum": ["minutes", "hours", "days"]],
                    "prerequisites": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Task numbers or UUIDs that must be done before this task"
                    ]
                ],
                "required": ["project", "title"]
            ])
        ),
        Tool(
            name: "update_task",
            description: "Update fields on an existing task. Only provided fields change. Pass \"none\" for priority or estimate_unit to clear that field.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "task": ["type": "string", "description": "Task number or UUID"],
                    "title": ["type": "string"],
                    "details": ["type": "string"],
                    "notes": ["type": "string"],
                    "category": ["type": "string", "description": "Pass \"none\" to clear"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "priority": ["type": "string", "enum": ["low", "medium", "high", "none"]],
                    "estimate_value": ["type": "number"],
                    "estimate_unit": ["type": "string", "enum": ["minutes", "hours", "days", "none"]]
                ],
                "required": ["project", "task"]
            ])
        ),
        Tool(
            name: "set_task_state",
            description: "Set a task's progress. A task that is blocked by unfinished prerequisites cannot be moved to in_progress or done — the error lists the blockers — unless force=true.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "task": ["type": "string", "description": "Task number or UUID"],
                    "state": ["type": "string", "enum": ["not_started", "in_progress", "done", "closed"]],
                    "force": ["type": "boolean", "description": "Override the blocked guard", "default": false]
                ],
                "required": ["project", "task", "state"]
            ])
        ),
        Tool(
            name: "add_dependency",
            description: "Add a dependency: `prerequisite` must be done before `dependent` can start. Rejects self-dependencies, duplicates, and cycles.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "prerequisite": ["type": "string", "description": "Task number or UUID of the prerequisite"],
                    "dependent": ["type": "string", "description": "Task number or UUID of the dependent task"]
                ],
                "required": ["project", "prerequisite", "dependent"]
            ])
        ),
        Tool(
            name: "remove_dependency",
            description: "Remove a dependency edge between two tasks.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "prerequisite": ["type": "string", "description": "Task number or UUID"],
                    "dependent": ["type": "string", "description": "Task number or UUID"]
                ],
                "required": ["project", "prerequisite", "dependent"]
            ])
        ),
        Tool(
            name: "delete_task",
            description: "Delete a task and every dependency edge that references it. This is irreversible.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "task": ["type": "string", "description": "Task number or UUID"]
                ],
                "required": ["project", "task"]
            ])
        ),
        Tool(
            name: "add_comment",
            description: "Add a comment to a task, e.g. investigation findings or how the task was resolved.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Project title or UUID"],
                    "task": ["type": "string", "description": "Task number or UUID"],
                    "text": ["type": "string"],
                    "author": ["type": "string", "description": "Defaults to \"agent\""]
                ],
                "required": ["project", "task", "text"]
            ])
        )
    ]
}
