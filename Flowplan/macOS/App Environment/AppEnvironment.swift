//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftUI
import SwiftData

/// An application-wide environment container.
///
/// This type centralizes access to shared app state and dependencies that are safe to
/// read from anywhere in the app, such as `AppSettings` and the `PlanStore`. Prefer injecting
/// instances via SwiftUI's `@Environment`.
///
/// Use ``AppEnvironment/default`` for the process-global environment that is created
/// lazily at launch based on build configuration and the `APP_ENVIRONMENT` process
/// environment variable.
///
/// - Important: Avoid creating your own instances unless you are writing previews or tests.
///
public final class AppEnvironment {

    // MARK: - Properties

    /// Application settings used throughout the app.
    public let appSettings: AppSettings

    /// The SwiftData container backing all plans.
    public let modelContainer: ModelContainer

    /// The mutation/validation/seeding layer over the container's main context.
    public let planStore: PlanStore

    /// Owns the embedded MCP server's lifecycle.
    public let mcpServerManager: MCPServerManager

    /// Engineering mode
    internal let engineeringMode: EngineeringMode

    // MARK: - Init

    /// Creates an environment with the provided dependencies.
    ///
    /// - Note: Use ``live()``/``mock()`` rather than this initializer.
    ///
    internal init(
        appSettings: AppSettings,
        modelContainer: ModelContainer,
        engineeringMode: EngineeringMode
    ) {
        self.appSettings = appSettings
        self.modelContainer = modelContainer
        let planStore = PlanStore(modelContext: modelContainer.mainContext)
        self.planStore = planStore
        self.mcpServerManager = MCPServerManager(
            appSettings: appSettings,
            service: MCPTaskService(planStore: planStore)
        )
        self.engineeringMode = engineeringMode
    }
}

extension AppEnvironment {

    /// Builds the SwiftData container for Flowplan's models.
    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([Plan.self, PlanTask.self, TaskDependency.self, TaskComment.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
