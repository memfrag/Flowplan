//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// A time estimate for completing a task.
nonisolated public struct TaskEstimate: Codable, Hashable, Sendable {
    public var value: Double
    public var unit: EstimateUnit

    public init(value: Double, unit: EstimateUnit) {
        self.value = value
        self.unit = unit
    }

    /// A short human-readable form, e.g. "3 days" or "1 hour".
    public var displayText: String {
        let rounded = value.rounded() == value ? String(Int(value)) : String(value)
        let singular = value == 1
        return "\(rounded) \(singular ? unit.singularName : unit.pluralName)"
    }
}

nonisolated public enum EstimateUnit: String, Codable, CaseIterable, Sendable, Identifiable, CustomStringConvertible {
    case minutes
    case hours
    case days

    public var id: Self { self }

    public var description: String { pluralName }

    public var singularName: String {
        switch self {
        case .minutes: "minute"
        case .hours: "hour"
        case .days: "day"
        }
    }

    public var pluralName: String {
        switch self {
        case .minutes: "minutes"
        case .hours: "hours"
        case .days: "days"
        }
    }
}
