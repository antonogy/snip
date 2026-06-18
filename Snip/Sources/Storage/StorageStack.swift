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
    let snippets: SnippetStore

    private let config = JSONConfigStore()
    private let log = AppLog.make("storage.stack")

    public init(directories: AppDirectories) throws {
        self.directories = directories
        self.content = ContentStore(directories: directories)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        self.database = try DatabaseQueue(path: directories.databaseURL.path, configuration: configuration)

        try Migrations.makeMigrator().migrate(database)
        self.snippets = SnippetStore(database: database)
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

    // MARK: - Single-snippet bootstrap (M1–M3 compatibility)

    /// Bootstraps a default snippet on first launch, or loads the existing active
    /// snippet. Returns the snippet and its current text content.
    public func loadOrBootstrap() throws -> (snippet: Snippet, content: String) {
        let snippet = try snippets.bootstrapIfNeeded()
        let text = try content.read(relativePath: snippet.mainEditor.contentFilePath)
        return (snippet, text)
    }

    /// Atomically writes text to the content file, then bumps `updated_at` in the DB.
    public func saveEditorContent(_ text: String, for doc: EditorDocument) throws {
        try content.write(text, relativePath: doc.contentFilePath)
        try snippets.touchEditorDocument(id: doc.id, at: Date())
    }

    // MARK: - Multi-snippet operations

    /// Returns all non-deleted snippets ordered pinned-first, newest-first.
    public func listSnippets() throws -> [Snippet] {
        try snippets.listSnippets()
    }

    /// Number of active (non-deleted) snippets, subject to the snippet cap (FR-21).
    public func activeSnippetCount() throws -> Int {
        try snippets.activeCount()
    }

    /// Creates a new snippet with an auto-generated title and an empty content file.
    /// Throws `StorageError.snippetLimitReached` when the active cap is hit (FR-21).
    public func createSnippet() throws -> Snippet {
        let snippet = try snippets.insertNewSnippet()
        try content.write("", relativePath: snippet.mainEditor.contentFilePath)
        return snippet
    }

    /// Soft-deletes a snippet into the recovery queue.
    public func deleteSnippet(id: UUID, gracePeriodDays: Int = 30) throws {
        try snippets.softDeleteSnippet(id: id, gracePeriodDays: gracePeriodDays, at: Date())
    }

    /// Permanently removes every active snippet whose editors are all empty
    /// (main and split, if present). Bypasses Recovery — there is nothing to
    /// recover. Intended to run once at launch (FR-1). Returns the count purged.
    @discardableResult
    public func purgeEmptySnippets() throws -> Int {
        var purged = 0
        for snippet in try snippets.listSnippets() {
            let mainEmpty = try content.isEmpty(relativePath: snippet.mainEditor.contentFilePath)
            let splitEmpty =
                try snippet.splitEditor
                .map { try content.isEmpty(relativePath: $0.contentFilePath) } ?? true
            guard mainEmpty, splitEmpty else { continue }
            for path in try snippets.purgeSnippet(id: snippet.id) {
                try content.remove(relativePath: path)
            }
            purged += 1
        }
        return purged
    }

    // MARK: - Recovery & expiration

    /// Returns every snippet in the recovery queue (deleted or expired), newest first.
    public func listRecoveryItems() throws -> [RecoveryItem] {
        try snippets.listRecoveryItems()
    }

    /// Restores a soft-deleted snippet to the active list, returning it hydrated.
    public func restoreSnippet(id: UUID) throws -> Snippet {
        try snippets.restoreSnippet(id: id)
    }

    /// Soft-deletes unpinned snippets idle beyond `expirationDays` into Recovery (FR-1).
    /// Returns the number expired. Intended to run once at launch as a cleanup job.
    @discardableResult
    public func expireStaleSnippets(
        expirationDays: Int,
        gracePeriodDays: Int = 30,
        now: Date = Date()
    ) throws -> Int {
        try snippets.expireStaleSnippets(
            now: now, expirationDays: expirationDays, gracePeriodDays: gracePeriodDays)
    }

    /// Permanently removes recovery items past their retention window, deleting their
    /// snippets, editor rows, and backing content files (FR-11). Returns the count
    /// purged. Intended to run once at launch as a cleanup job.
    @discardableResult
    public func purgeExpiredRecoveryItems(now: Date = Date()) throws -> Int {
        var purged = 0
        for id in try snippets.expiredRecoverySnippetIds(now: now) {
            for path in try snippets.purgeSnippet(id: id) {
                try content.remove(relativePath: path)
            }
            purged += 1
        }
        return purged
    }

    /// Toggles the pinned state of a snippet, which affects list ordering.
    public func setSnippetPinned(id: UUID, isPinned: Bool) throws {
        try snippets.setPinned(id: id, isPinned: isPinned)
    }

    /// Reads the text content for an editor document.
    public func loadSnippetContent(for doc: EditorDocument) throws -> String {
        try content.read(relativePath: doc.contentFilePath)
    }

    // MARK: - Split editor

    /// Adds a split editor to the snippet (or re-orients an existing one). A newly
    /// created split starts with an empty content file. Returns the updated snippet.
    public func setSplit(snippetId: UUID, orientation: SplitOrientation) throws -> Snippet {
        let result = try snippets.setSplit(snippetId: snippetId, orientation: orientation)
        if let path = result.createdEditorPath {
            try content.write("", relativePath: path)
        }
        return result.snippet
    }

    /// Removes the snippet's split editor and deletes its backing content file.
    public func closeSplit(snippetId: UUID) throws -> Snippet {
        let result = try snippets.closeSplit(snippetId: snippetId)
        if let path = result.removedEditorPath {
            try content.remove(relativePath: path)
        }
        return result.snippet
    }

    // MARK: - Language

    /// Sets the main editor's language and detection mode, regenerating the
    /// automatic title to match. Returns the updated snippet.
    public func setMainLanguage(
        snippetId: UUID,
        language: CodeLanguage,
        mode: LanguageMode
    ) throws -> Snippet {
        try snippets.setMainEditorLanguage(
            snippetId: snippetId, language: language, mode: mode, regenerateTitle: true)
    }

    /// Sets the split editor's language and detection mode (independent of the
    /// main editor; never affects the title). Returns the updated snippet.
    public func setSplitLanguage(
        snippetId: UUID,
        language: CodeLanguage,
        mode: LanguageMode
    ) throws -> Snippet {
        try snippets.setSplitEditorLanguage(snippetId: snippetId, language: language, mode: mode)
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
    case contentReadFailed(String)
    case missingSnippet(String)
    case snippetLimitReached(Int)

    public var description: String {
        switch self {
        case .missingTable(let name): return "Expected table '\(name)' is missing"
        case .contentReadFailed(let path): return "Failed to read content file at '\(path)'"
        case .missingSnippet(let id): return "Snippet '\(id)' not found"
        case .snippetLimitReached(let max): return "Snippet limit reached (\(max))"
        }
    }
}
