//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// The user-facing state of a task, derived from its ``TaskProgress`` and its dependencies.
///
/// `Backlog` and `readyToStart` are *computed*, never stored: a task is `backlog` when it is
/// not done but has at least one unfinished dependency, and `readyToStart` when it is not yet
/// started but all of its dependencies are done.
nonisolated public enum TaskDisplayState: String, Codable, CaseIterable, Sendable, Identifiable, CustomStringConvertible {
    case backlog
    case readyToStart
    case inProgress
    case done
    case closed

    public var id: Self { self }

    public var description: String {
        switch self {
        case .backlog: "Blocked"
        case .readyToStart: "Ready to Start"
        case .inProgress: "In Progress"
        case .done: "Done"
        case .closed: "Closed"
        }
    }

    /// SF Symbol representing the state. Colour is never used alone — always paired with an icon.
    public var systemImage: String {
        switch self {
        case .backlog: "lock.fill"
        case .readyToStart: "play.circle.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        case .closed: "xmark.circle.fill"
        }
    }

    /// Accent colour for the state, per the spec's §8.1 palette.
    public var color: Color {
        switch self {
        case .backlog: .secondary
        case .readyToStart: .blue
        case .inProgress: .orange
        case .done: .green
        case .closed: .gray
        }
    }

    /// Whether the user is allowed to start a task in this state.
    public var isStartable: Bool {
        self == .readyToStart
    }
}
