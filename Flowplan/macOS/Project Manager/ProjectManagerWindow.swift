//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// A separate window for managing project-level metadata (description, associated repositories)
/// across all plans.
struct ProjectManagerWindow: Scene {

    static let windowID = "project-manager"

    var body: some Scene {
        Window("Project Manager", id: Self.windowID) {
            ProjectManagerView()
                .frame(minWidth: 680, minHeight: 440)
                .appEnvironment(.default)
        }
        .defaultSize(width: 820, height: 560)
    }
}
