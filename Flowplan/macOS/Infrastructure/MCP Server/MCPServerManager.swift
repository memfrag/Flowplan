//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog

/// Owns the embedded MCP server's lifecycle, reacting to ``AppSettings/mcpServerEnabled`` and
/// ``AppSettings/mcpServerPort`` so the Settings UI never has to restart the server explicitly.
@Observable @MainActor
public final class MCPServerManager {

    public enum Status: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case failed(String)
    }

    public private(set) var status: Status = .stopped

    /// The server's MCP endpoint URL while running.
    public var url: URL? {
        if case .running(let port) = status {
            return URL(string: "http://127.0.0.1:\(port)/mcp")
        }
        return nil
    }

    @ObservationIgnored
    private let appSettings: AppSettings
    @ObservationIgnored
    private let service: MCPTaskService
    @ObservationIgnored
    private var controller: MCPServerController?
    /// Bumped on every sync so a stale, superseded start/stop can be ignored when it completes.
    @ObservationIgnored
    private var generation = 0

    private static let log = Logger(subsystem: "io.apparata.Flowplan", category: "MCPServerManager")

    init(appSettings: AppSettings, service: MCPTaskService) {
        self.appSettings = appSettings
        self.service = service
    }

    /// Starts observing settings and performs the initial sync. Call once at launch.
    public func applyAtLaunch() {
        observeSettings()
        Task { await syncWithSettings() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = appSettings.mcpServerEnabled
            _ = appSettings.mcpServerPort
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncWithSettings()
                self.observeSettings()
            }
        }
    }

    private func syncWithSettings() async {
        generation += 1
        let myGeneration = generation

        if let controller {
            self.controller = nil
            await controller.stop()
        }
        guard myGeneration == generation else { return }

        guard appSettings.mcpServerEnabled else {
            status = .stopped
            return
        }

        let port = appSettings.mcpServerPort
        guard (1024...65535).contains(port) else {
            status = .failed("Port must be between 1024 and 65535.")
            return
        }

        status = .starting
        let service = self.service
        let newController = MCPServerController(
            configuration: .init(port: port),
            serverFactory: { _, _ in await FlowplanMCPServerFactory.makeServer(service: service) }
        )

        do {
            try await newController.start()
            guard myGeneration == generation else {
                await newController.stop()
                return
            }
            controller = newController
            status = .running(port: port)
        } catch {
            guard myGeneration == generation else { return }
            Self.log.error("Failed to start MCP server on port \(port): \(error.localizedDescription)")
            status = .failed("Port \(port) is already in use, or could not be bound.")
        }
    }
}
