//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// JSON response shapes returned by MCP tools. Distinct from ``PlanDTO``/``TaskDTO`` (the
/// `.flowplan` file format): these are agent-facing, include the *derived* display state, and omit
/// canvas positions.
nonisolated struct ProjectSnapshot: Codable, Sendable {
    var id: UUID
    var title: String
    var summary: String?
    /// The group the project belongs to, or `nil` when ungrouped.
    var group: String?
    var repositoryURLs: [String]
    /// Task counts keyed by derived state (`blocked`, `ready`, `in_progress`, `done`, `closed`).
    var taskCounts: [String: Int]
    var updatedAt: Date
}

nonisolated struct TaskRef: Codable, Sendable {
    var number: Int
    var title: String
    var state: String
}

nonisolated struct CommentSnapshot: Codable, Sendable {
    var author: String
    var text: String
    var createdAt: Date
}

nonisolated struct CriticalPathSnapshot: Codable, Sendable {
    /// Human-readable total duration, e.g. "5 days".
    var totalDuration: String
    var totalDurationHours: Double
    var taskCount: Int
    /// The critical chain in dependency order (prerequisite → dependent).
    var path: [TaskRef]
}

nonisolated struct TaskSnapshot: Codable, Sendable {
    var id: UUID
    var number: Int
    var title: String
    var details: String?
    var notes: String?
    /// The stored progress: `not_started`, `in_progress`, `done`, `closed`.
    var progress: String
    /// The derived display state: `blocked`, `ready`, `in_progress`, `done`, `closed`.
    var state: String
    var category: String?
    var tags: [String]
    var priority: String?
    var estimate: String?
    var dueDate: Date?
    var overdue: Bool
    var blockedBy: [TaskRef]
    var prerequisites: [TaskRef]
    var dependents: [TaskRef]
    var comments: [CommentSnapshot]
    var createdAt: Date
    var updatedAt: Date
}

extension TaskDisplayState {
    /// The wire-format string used in MCP snapshots for this derived state.
    var mcpValue: String {
        switch self {
        case .backlog: "blocked"
        case .readyToStart: "ready"
        case .inProgress: "in_progress"
        case .done: "done"
        case .closed: "closed"
        }
    }
}

extension TaskProgress {
    /// The wire-format string used in MCP snapshots for this stored progress.
    var mcpValue: String {
        switch self {
        case .notStarted: "not_started"
        case .inProgress: "in_progress"
        case .done: "done"
        case .closed: "closed"
        }
    }

    init?(mcpValue: String) {
        switch mcpValue {
        case "not_started": self = .notStarted
        case "in_progress": self = .inProgress
        case "done": self = .done
        case "closed": self = .closed
        default: return nil
        }
    }
}

extension TaskPriority {
    init?(mcpValue: String) {
        self.init(rawValue: mcpValue)
    }
}

extension EstimateUnit {
    init?(mcpValue: String) {
        self.init(rawValue: mcpValue)
    }
}

// MARK: - JSON encoding

nonisolated enum MCPJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Encodes any `Encodable` snapshot to a compact JSON string, for use as tool-call text output.
    static func string(_ value: some Encodable) -> String {
        guard let data = try? makeEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
