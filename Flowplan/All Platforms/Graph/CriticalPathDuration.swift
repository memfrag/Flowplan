//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Bridges ``PlanTask`` estimates into the duration map the pure ``TaskGraph/criticalPath(durations:)``
/// engine expects. Unestimated tasks get a nominal one-day duration so the critical path stays
/// meaningful even when estimates are sparse (it then degrades to the longest dependency chain).
@MainActor
enum CriticalPathDuration {

    /// Hours assumed for a task with no estimate.
    static let defaultHours: Double = 24

    static func durations(for tasks: [PlanTask]) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for task in tasks {
            result[task.id] = task.estimate?.hours ?? defaultHours
        }
        return result
    }
}
