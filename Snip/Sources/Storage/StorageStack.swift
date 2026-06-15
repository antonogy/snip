import Foundation
import GRDB
import SharedModels
import SharedUtilities

/// Snapshot of everything restored from disk at launch.
public struct RestoredState: Sendable, Equatable {
    public var settings: Settings
    public var appState: AppState

    public init(settings: Settings, appState: AppState) {
        self.settings = settings
        self.appState = appState
    }
}

/// The composition root for persistence. Owns the migrated database and the
/// stores for JSON config and content files.
///
/// Constructing the stack performs all blocking setup (directory creation,
/// opening the database, running migrations), so it should be built once at
/// launch. All stored members are thread-safe, so the stack is `Sendable`.
public final class StorageStack: Sendable {
    public let directories: AppDirectories
    public let database: DatabaseQueue
    public let content: ContentStore

    private let config = JSONConfigStore()
    private let log = AppLog.make("storage.stack")

    public init(directories: AppDirectories) throws {
        self.directories = directories
        self.content = ContentStore(directories: directories)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        self.database = try DatabaseQueue(path: directories.databaseURL.path, configuration: configuration)

        try Migrations.makeMigrator().migrate(database)
        log.info("Storage initialized at \(directories.root.path, privacy: .public)")
    }

    // MARK: - Config

    public func loadSettings() -> Settings {
        config.load(Settings.self, from: directories.settingsURL, fallback: .default)
    }

    public func saveSettings(_ settings: Settings) throws {
        try config.save(settings, to: directories.settingsURL)
    }

    public func loadAppState() -> AppState {
        config.load(AppState.self, from: directories.appStateURL, fallback: .default)
    }

    public func saveAppState(_ appState: AppState) throws {
        try config.save(appState, to: directories.appStateURL)
    }

    // MARK: - Restoration

    /// Loads settings and UI state for startup restoration.
    public func restore() -> RestoredState {
        RestoredState(settings: loadSettings(), appState: loadAppState())
    }

    /// Confirms the database is migrated to the expected schema. Used by the
    /// `--self-check` launch path and integration tests.
    public func verifySchema() throws {
        try database.read { db in
            for table in Migrations.expectedTables {
                guard try db.tableExists(table) else {
                    throw StorageError.missingTable(table)
                }
            }
        }
    }
}

public enum StorageError: Error, CustomStringConvertible {
    case missingTable(String)

    public var description: String {
        switch self {
        case .missingTable(let name): return "Expected table '\(name)' is missing"
        }
    }
}
