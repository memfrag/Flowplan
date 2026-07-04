//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    let updater: SPUUpdater

    var body: some Scene {

        WindowGroup {
            FlowplanWindow()
                .frame(minWidth: 900, minHeight: 560)
                .appEnvironment(.default)
                #if os(macOS)
                .terminatesAppWhenClosed()
                #endif
        }
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            SidebarCommands()
            TaskCommands()
            FlowplanExportCommands()
            HelpCommands()
        }
    }
}
