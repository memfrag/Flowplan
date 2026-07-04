//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// The stored, manually-set progress of a task.
///
/// This is the *internal* progress model. The user-facing state shown in the UI is
/// derived from this plus the task's dependencies — see ``TaskDisplayState``.
nonisolated public enum TaskProgress: String, Codable, CaseIterable, Sendable, Identifiable, CustomStringConvertible {
    case notStarted
    case inProgress
    case done

    public var id: Self { self }

    public var description: String {
        switch self {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}
