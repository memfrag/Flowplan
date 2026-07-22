//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftUI
import SwiftData
import OSLog

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
    ///
    /// The on-disk store syncs via CloudKit (`.automatic` reads the iCloud container from the app's
    /// entitlement and mirrors to the user's private database). If CloudKit is unavailable — no
    /// entitlement, unsigned/ad-hoc build, etc. — it falls back to a local-only store so the app
    /// still runs. In-memory stores (previews/tests) never use CloudKit.
    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([Plan.self, PlanTask.self, TaskDependency.self, TaskComment.self])

        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return (try? ModelContainer(for: schema, configurations: [configuration]))
                ?? fatalContainer(schema: schema)
        }

        let url = storeURL()
        let cloudConfiguration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .automatic)
        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            Self.log.info("Model container created with CloudKit sync enabled.")
            return container
        } catch {
            // The specific reason (e.g. a CloudKit schema-compatibility violation) is logged by the
            // `com.apple.coredata` subsystem, not carried on this wrapped SwiftDataError.
            Self.log.error("CloudKit unavailable — using a local store. \(error, privacy: .public)")
        }

        // CloudKit unavailable — fall back to a local store.
        let localConfiguration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return (try? ModelContainer(for: schema, configurations: [localConfiguration]))
            ?? fatalContainer(schema: schema)
    }

    /// The on-disk store location, kept in an app-specific subdirectory.
    ///
    /// This must stay explicit. `ModelConfiguration` without a URL writes to
    /// `Application Support/default.store` — a filename that is *not* namespaced by bundle
    /// identifier. A sandboxed app gets away with it because its Application Support lives inside its
    /// container; an unsandboxed one (which Flowplan is) writes to the user-wide
    /// `~/Library/Application Support`, where every unsandboxed SwiftData app collides on the same
    /// file. Two apps with different schemas then migrate that file back and forth, each dropping the
    /// other's entities, which strands live objects on rows that no longer exist.
    private static func storeURL() -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Flowplan", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Flowplan.store")
    }

    private static let log = Logger(subsystem: "io.apparata.Flowplan", category: "ModelContainer")

    private static func fatalContainer(schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
