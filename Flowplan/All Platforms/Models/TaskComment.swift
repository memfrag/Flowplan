//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftData

/// A comment on a ``PlanTask`` — e.g. investigation findings, or notes about how the task was
/// resolved. Comments come from the user (via the inspector) or from an agent (via the MCP server).
@Model
public final class TaskComment {

    // CloudKit-compatible: no unique constraint, every property optional or defaulted (see ``Plan``).
    public var id: UUID = UUID()

    /// Who wrote the comment — `"user"` for comments added in the app, or an agent name.
    public var author: String = ""

    public var text: String = ""

    public var createdAt: Date = Date.now

    /// The task this comment belongs to. Inverse of ``PlanTask/comments``.
    public var task: PlanTask?

    public init(
        id: UUID = UUID(),
        author: String,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
    }
}
