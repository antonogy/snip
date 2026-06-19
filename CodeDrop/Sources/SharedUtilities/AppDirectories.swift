import Foundation

/// Resolves the on-disk layout of the storage container and guarantees the
/// directories exist.
///
/// Layout (matches the product spec):
/// ```
/// <root>/
/// ├─ metadata.sqlite
/// ├─ app_state.json
/// ├─ settings.json
/// └─ contents/
/// ```
///
/// Inject a custom `root` (e.g. a temp directory) in tests; production uses
/// `makeDefault()`, which lives under Application Support.
public struct AppDirectories: Sendable, Equatable {
    /// Folder name used under Application Support in production.
    public static let containerFolderName = "CodeDrop"

    public let root: URL

    public var databaseURL: URL { root.appendingPathComponent("metadata.sqlite") }
    public var appStateURL: URL { root.appendingPathComponent("app_state.json") }
    public var settingsURL: URL { root.appendingPathComponent("settings.json") }
    public var contentsURL: URL { root.appendingPathComponent("contents", isDirectory: true) }

    /// Creates the value and ensures `root` and `contents/` exist on disk.
    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    }

    /// Production locations under `~/Library/Application Support/CodeDrop`.
    public static func makeDefault(fileManager: FileManager = .default) throws -> AppDirectories {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent(containerFolderName, isDirectory: true)
        return try AppDirectories(root: root, fileManager: fileManager)
    }
}
