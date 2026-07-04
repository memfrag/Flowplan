//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// The relative priority of a task.
nonisolated public enum TaskPriority: String, Codable, CaseIterable, Sendable, Identifiable, CustomStringConvertible {
    case low
    case medium
    case high

    public var id: Self { self }

    public var description: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public var systemImage: String {
        switch self {
        case .low: "arrow.down"
        case .medium: "equal"
        case .high: "exclamationmark.2"
        }
    }

    public var color: Color {
        switch self {
        case .low: .secondary
        case .medium: .blue
        case .high: .red
        }
    }
}
