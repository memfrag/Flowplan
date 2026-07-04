//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Drives the main sidebar list selection (spec §7.3).
///
/// Plan (project) switching is handled separately from this enum so that the active plan and the
/// active view/focus can be highlighted independently, matching the mockup.
enum SidebarSelection: Hashable {
    case overview
    case mode(PlanViewMode)
    case focus(TaskDisplayState)
}
