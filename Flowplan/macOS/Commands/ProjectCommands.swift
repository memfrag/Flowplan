//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Adds a "Project Manager…" item to the menu bar for editing project metadata.
struct ProjectCommands: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Project Manager…") {
                openWindow(id: ProjectManagerWindow.windowID)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}
