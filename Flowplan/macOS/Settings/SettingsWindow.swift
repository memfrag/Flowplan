//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Show settings window by using a SettingsLink SwiftUI view.
struct SettingsWindow: Scene {

    private enum Tabs: Hashable {
        case mcp
    }

    var body: some Scene {
        Settings {
            tabs
                .appEnvironment(.default)
        }
    }

    @ViewBuilder var tabs: some View {
        TabView {
            MCPSettingsTab()
                .tabItem {
                    Label("MCP Server", systemImage: "server.rack")
                }
                .tag(Tabs.mcp)
        }
    }
}
