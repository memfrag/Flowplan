//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

/// Enable/disable the embedded MCP server and configure its localhost port. Lets an external agent
/// (e.g. Claude Code) read and steer tasks over MCP — see ``MCPServerManager``.
struct MCPSettingsTab: View {

    @Environment(AppSettings.self) private var appSettings
    @Environment(MCPServerManager.self) private var serverManager

    @State private var didCopyCommand = false

    var body: some View {
        @Bindable var settings = appSettings

        Form {
            Section {
                Toggle("Enable MCP server", isOn: $settings.mcpServerEnabled)

                LabeledContent("Port:") {
                    TextField(
                        "Port",
                        value: $settings.mcpServerPort,
                        format: .number.grouping(.never)
                    )
                    .labelsHidden()
                    .frame(width: 80)
                }
                .disabled(!settings.mcpServerEnabled)
            }

            Section {
                statusRow
                if let url = serverManager.url {
                    let command = "claude mcp add --transport http flowplan \(url.absoluteString)"
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add to Claude Code:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(command)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                copyCommand(command)
                            } label: {
                                Image(systemName: didCopyCommand ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy command")
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 260)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch serverManager.status {
        case .stopped:
            Label("Stopped", systemImage: "circle.fill")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "circle.fill")
                .foregroundStyle(.yellow)
        case .running(let port):
            Label("Running at http://127.0.0.1:\(String(port))/mcp", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .textSelection(.enabled)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    /// Copies `command` to the pasteboard and briefly shows a checkmark on the copy button.
    private func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopyCommand = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyCommand = false
        }
    }
}

#if DEBUG
#Preview {
    let settings = AppSettings.mock()
    let planStore = PlanStore(modelContext: AppEnvironment.makeModelContainer(inMemory: true).mainContext)
    MCPSettingsTab()
        .environment(settings)
        .environment(MCPServerManager(appSettings: settings, service: MCPTaskService(planStore: planStore)))
}
#endif
