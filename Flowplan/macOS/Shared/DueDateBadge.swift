//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A compact due-date indicator, styled red with a warning icon when the task is overdue. Renders
/// nothing when the task has no due date.
struct DueDateBadge: View {

    let task: PlanTask
    var showsIcon: Bool = true

    var body: some View {
        if let dueDate = task.dueDate {
            let overdue = task.isOverdue
            HStack(spacing: 3) {
                if showsIcon {
                    Image(systemName: overdue ? "calendar.badge.exclamationmark" : "calendar")
                }
                Text(dueDate.formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(.caption2)
            .foregroundStyle(overdue ? Color.red : Color.secondary)
            .help(overdue ? "Overdue" : "Due date")
        }
    }
}
