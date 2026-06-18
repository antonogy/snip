import Foundation
import GRDB
import SharedModels

// MARK: - GRDB record types (internal to Storage module)

struct EditorDocumentRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "editor_documents"

    var id: String
    var contentFilePath: String
    var language: String
    var languageMode: String
    var cursorPosition: Int?
    var selectedRangeLocation: Int?
    var selectedRangeLength: Int?
    var scrollOffset: Double?
    var createdAt: Date
    var updatedAt: Date

    init(row: Row) throws {
        id = row["id"]
        contentFilePath = row["content_file_path"]
        language = row["language"]
        languageMode = row["language_mode"]
        cursorPosition = row["cursor_position"]
        selectedRangeLocation = row["selected_range_location"]
        selectedRangeLength = row["selected_range_length"]
        scrollOffset = row["scroll_offset"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["content_file_path"] = contentFilePath
        container["language"] = language
        container["language_mode"] = languageMode
        container["cursor_position"] = cursorPosition
        container["selected_range_location"] = selectedRangeLocation
        container["selected_range_length"] = selectedRangeLength
        container["scroll_offset"] = scrollOffset
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    init(from doc: EditorDocument) {
        id = doc.id.uuidString
        contentFilePath = doc.contentFilePath
        language = doc.language.rawValue
        languageMode = doc.languageMode.rawValue
        cursorPosition = doc.cursorPosition
        selectedRangeLocation = doc.selectedRange?.location
        selectedRangeLength = doc.selectedRange?.length
        scrollOffset = doc.scrollOffset
        createdAt = doc.createdAt
        updatedAt = doc.updatedAt
    }

    func toModel() -> EditorDocument {
        let range: SharedModels.TextRange?
        if let loc = selectedRangeLocation, let len = selectedRangeLength {
            range = SharedModels.TextRange(location: loc, length: len)
        } else {
            range = nil
        }
        return EditorDocument(
            id: UUID(uuidString: id) ?? UUID(),
            contentFilePath: contentFilePath,
            language: CodeLanguage(rawValue: language) ?? .plainText,
            languageMode: LanguageMode(rawValue: languageMode) ?? .auto,
            cursorPosition: cursorPosition,
            selectedRange: range,
            scrollOffset: scrollOffset,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct SnippetRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "snippets"

    var id: String
    var title: String
    var titleSource: String
    var mainEditorId: String
    var splitEditorId: String?
    var splitOrientation: String?
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var expiresAt: Date?
    var deletedAt: Date?

    init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        titleSource = row["title_source"]
        mainEditorId = row["main_editor_id"]
        splitEditorId = row["split_editor_id"]
        splitOrientation = row["split_orientation"]
        isPinned = row["is_pinned"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
        lastOpenedAt = row["last_opened_at"]
        expiresAt = row["expires_at"]
        deletedAt = row["deleted_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["title"] = title
        container["title_source"] = titleSource
        container["main_editor_id"] = mainEditorId
        container["split_editor_id"] = splitEditorId
        container["split_orientation"] = splitOrientation
        container["is_pinned"] = isPinned
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["last_opened_at"] = lastOpenedAt
        container["expires_at"] = expiresAt
        container["deleted_at"] = deletedAt
    }

    init(from snippet: Snippet) {
        id = snippet.id.uuidString
        title = snippet.title
        titleSource = snippet.titleSource.rawValue
        mainEditorId = snippet.mainEditor.id.uuidString
        splitEditorId = snippet.splitEditor?.id.uuidString
        splitOrientation = snippet.splitOrientation?.rawValue
        isPinned = snippet.isPinned
        createdAt = snippet.createdAt
        updatedAt = snippet.updatedAt
        lastOpenedAt = snippet.lastOpenedAt
        expiresAt = snippet.expiresAt
        deletedAt = snippet.deletedAt
    }

    func toSnippet(mainEditor: EditorDocument, splitEditor: EditorDocument? = nil) -> Snippet {
        Snippet(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            titleSource: SnippetTitleSource(rawValue: titleSource) ?? .automatic,
            mainEditor: mainEditor,
            splitEditor: splitEditor,
            splitOrientation: splitOrientation.flatMap { SplitOrientation(rawValue: $0) },
            isPinned: isPinned,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastOpenedAt: lastOpenedAt,
            expiresAt: expiresAt,
            deletedAt: deletedAt
        )
    }
}

// MARK: - SnippetStore

/// Handles CRUD for snippets and their editor documents in the metadata database.
struct SnippetStore: Sendable {
    private let database: DatabaseQueue

    init(database: DatabaseQueue) {
        self.database = database
    }

    /// Ensures at least one active snippet exists. Creates a default on first
    /// launch; returns the first active snippet on subsequent launches.
    func bootstrapIfNeeded() throws -> Snippet {
        try database.write { db in
            let count =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snippets WHERE deleted_at IS NULL") ?? 0
            if count == 0 {
                return try insertDefaultSnippet(db)
            }
            guard let snippet = try fetchFirstSnippet(db) else {
                return try insertDefaultSnippet(db)
            }
            return snippet
        }
    }

    func loadSnippet(id: UUID) throws -> Snippet? {
        try database.read { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: id.uuidString) else { return nil }
            return try hydrate(sr, db)
        }
    }

    func upsertEditorDocument(_ doc: EditorDocument) throws {
        try database.write { db in
            try EditorDocumentRecord(from: doc).save(db)
        }
    }

    func upsertSnippet(_ snippet: Snippet) throws {
        try database.write { db in
            try EditorDocumentRecord(from: snippet.mainEditor).save(db)
            if let split = snippet.splitEditor {
                try EditorDocumentRecord(from: split).save(db)
            }
            try SnippetRecord(from: snippet).save(db)
        }
    }

    /// Lightweight hot-path update: only bumps `updated_at` on the editor document.
    func touchEditorDocument(id: UUID, at date: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE editor_documents SET updated_at = ? WHERE id = ?",
                arguments: [date, id.uuidString]
            )
        }
    }

    // MARK: - Multi-snippet operations

    func listSnippets() throws -> [Snippet] {
        try database.read { db in
            try fetchAllSnippets(db)
        }
    }

    /// Number of active (non-deleted) snippets — the count subject to the
    /// snippet cap (FR-21). Excludes anything held in Recovery.
    func activeCount() throws -> Int {
        try database.read { db in
            try activeCount(db)
        }
    }

    func insertNewSnippet(language: CodeLanguage = .plainText, now: Date = Date()) throws -> Snippet {
        try database.write { db in
            guard try activeCount(db) < Limits.maxActiveSnippets else {
                throw StorageError.snippetLimitReached(Limits.maxActiveSnippets)
            }
            let editorID = UUID()
            let title = try nextTitle(for: language, in: db)
            let doc = EditorDocument(
                id: editorID,
                contentFilePath: ContentStore.fileName(for: editorID),
                language: language,
                languageMode: .auto,
                createdAt: now,
                updatedAt: now
            )
            let snippet = Snippet(
                id: UUID(),
                title: title,
                titleSource: .automatic,
                mainEditor: doc,
                isPinned: false,
                createdAt: now,
                updatedAt: now
            )
            try EditorDocumentRecord(from: doc).insert(db)
            try SnippetRecord(from: snippet).insert(db)
            return snippet
        }
    }

    func softDeleteSnippet(id: UUID, gracePeriodDays: Int, at date: Date) throws {
        try database.write { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: id.uuidString) else { return }
            let purgeAfter = date.addingTimeInterval(Double(gracePeriodDays) * 24 * 60 * 60)
            try db.execute(
                sql: "UPDATE snippets SET deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [date, date, id.uuidString]
            )
            try db.execute(
                sql: """
                    INSERT INTO recovery_items (id, snippet_id, title, deleted_at, purge_after)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, id.uuidString, sr.title, date, purgeAfter]
            )
        }
    }

    /// Permanently removes a snippet and its editor documents. Unlike
    /// `softDeleteSnippet`, this bypasses Recovery. Returns the content-file paths
    /// of the removed editors so the caller can delete them from disk.
    func purgeSnippet(id: UUID) throws -> [String] {
        try database.write { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: id.uuidString) else { return [] }
            var paths: [String] = []
            if let main = try EditorDocumentRecord.fetchOne(db, key: sr.mainEditorId) {
                paths.append(main.contentFilePath)
            }
            if let splitId = sr.splitEditorId,
                let split = try EditorDocumentRecord.fetchOne(db, key: splitId)
            {
                paths.append(split.contentFilePath)
            }
            // Delete the snippet row first: main_editor_id is an ON DELETE RESTRICT
            // foreign key, so the editor rows can only go once the snippet is gone.
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id.uuidString])
            try db.execute(
                sql: "DELETE FROM editor_documents WHERE id = ?", arguments: [sr.mainEditorId])
            if let splitId = sr.splitEditorId {
                try db.execute(sql: "DELETE FROM editor_documents WHERE id = ?", arguments: [splitId])
            }
            try db.execute(
                sql: "DELETE FROM recovery_items WHERE snippet_id = ?", arguments: [id.uuidString])
            return paths
        }
    }

    // MARK: - Recovery & expiration

    /// Returns every snippet currently in the recovery queue, newest deletion first.
    func listRecoveryItems() throws -> [RecoveryItem] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, snippet_id, title, deleted_at, purge_after
                    FROM recovery_items
                    ORDER BY deleted_at DESC
                    """
            ).map { row in
                RecoveryItem(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    snippetId: UUID(uuidString: row["snippet_id"]) ?? UUID(),
                    title: row["title"],
                    deletedAt: row["deleted_at"],
                    purgeAfter: row["purge_after"]
                )
            }
        }
    }

    /// Brings a soft-deleted snippet back to the active list: clears `deleted_at`,
    /// removes its recovery row, and bumps `updated_at` so the expiry clock restarts
    /// (otherwise a previously-stale snippet would re-expire on the next launch).
    func restoreSnippet(id: UUID, now: Date = Date()) throws -> Snippet {
        try database.write { db in
            guard try SnippetRecord.fetchOne(db, key: id.uuidString) != nil else {
                throw StorageError.missingSnippet(id.uuidString)
            }
            try db.execute(
                sql: "UPDATE snippets SET deleted_at = NULL, updated_at = ? WHERE id = ?",
                arguments: [now, id.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM recovery_items WHERE snippet_id = ?", arguments: [id.uuidString])
            let refreshed = try SnippetRecord.fetchOne(db, key: id.uuidString)!
            return try hydrate(refreshed, db)!
        }
    }

    /// Soft-deletes every unpinned, non-deleted snippet whose most recent activity is
    /// older than `expirationDays` (FR-1). "Activity" is the latest `updated_at` across
    /// the snippet row and its editor documents — the autosave hot path only bumps the
    /// editor's timestamp, so the snippet row alone would understate real edits.
    /// Returns the number of snippets expired.
    @discardableResult
    func expireStaleSnippets(now: Date, expirationDays: Int, gracePeriodDays: Int) throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(expirationDays) * 24 * 60 * 60)
        let purgeAfter = now.addingTimeInterval(Double(gracePeriodDays) * 24 * 60 * 60)
        return try database.write { db in
            let ids = try String.fetchAll(
                db,
                sql: """
                    SELECT s.id FROM snippets s
                    JOIN editor_documents m ON m.id = s.main_editor_id
                    LEFT JOIN editor_documents sp ON sp.id = s.split_editor_id
                    WHERE s.deleted_at IS NULL AND s.is_pinned = 0
                      AND MAX(s.updated_at, m.updated_at, COALESCE(sp.updated_at, s.updated_at)) < ?
                    """,
                arguments: [cutoff]
            )
            for id in ids {
                guard let sr = try SnippetRecord.fetchOne(db, key: id) else { continue }
                try db.execute(
                    sql: "UPDATE snippets SET deleted_at = ?, updated_at = ? WHERE id = ?",
                    arguments: [now, now, id]
                )
                try db.execute(
                    sql: """
                        INSERT INTO recovery_items (id, snippet_id, title, deleted_at, purge_after)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, id, sr.title, now, purgeAfter]
                )
            }
            return ids.count
        }
    }

    /// Returns the snippet ids of recovery rows whose retention window has elapsed,
    /// so the caller can permanently `purgeSnippet` each.
    func expiredRecoverySnippetIds(now: Date) throws -> [UUID] {
        try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT snippet_id FROM recovery_items WHERE purge_after <= ?",
                arguments: [now]
            ).compactMap { UUID(uuidString: $0) }
        }
    }

    func setPinned(id: UUID, isPinned: Bool, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE snippets SET is_pinned = ?, updated_at = ? WHERE id = ?",
                arguments: [isPinned, date, id.uuidString]
            )
        }
    }

    // MARK: - Split editor

    /// Creates the snippet's split editor (inheriting the main editor's language) or,
    /// if one already exists, just re-orients it — enforcing the "one split only" rule.
    /// Returns the hydrated snippet and, when a new editor was created, its content path
    /// so the caller can write the (empty) backing file.
    func setSplit(
        snippetId: UUID,
        orientation: SplitOrientation,
        now: Date = Date()
    ) throws -> (snippet: Snippet, createdEditorPath: String?) {
        try database.write { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: snippetId.uuidString) else {
                throw StorageError.missingSnippet(snippetId.uuidString)
            }

            if sr.splitEditorId == nil {
                guard let mainRec = try EditorDocumentRecord.fetchOne(db, key: sr.mainEditorId) else {
                    throw StorageError.missingSnippet(snippetId.uuidString)
                }
                let editorID = UUID()
                let doc = EditorDocument(
                    id: editorID,
                    contentFilePath: ContentStore.fileName(for: editorID),
                    language: mainRec.toModel().language,
                    languageMode: .auto,
                    createdAt: now,
                    updatedAt: now
                )
                try EditorDocumentRecord(from: doc).insert(db)
                try db.execute(
                    sql: """
                        UPDATE snippets
                        SET split_editor_id = ?, split_orientation = ?, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [editorID.uuidString, orientation.rawValue, now, snippetId.uuidString]
                )
                let refreshed = try SnippetRecord.fetchOne(db, key: snippetId.uuidString)!
                return (try hydrate(refreshed, db)!, doc.contentFilePath)
            } else {
                try db.execute(
                    sql: "UPDATE snippets SET split_orientation = ?, updated_at = ? WHERE id = ?",
                    arguments: [orientation.rawValue, now, snippetId.uuidString]
                )
                let refreshed = try SnippetRecord.fetchOne(db, key: snippetId.uuidString)!
                return (try hydrate(refreshed, db)!, nil)
            }
        }
    }

    /// Removes the snippet's split editor: clears the references, deletes the orphaned
    /// editor-document row, and returns the removed editor's content path for file cleanup.
    func closeSplit(snippetId: UUID, now: Date = Date()) throws -> (
        snippet: Snippet, removedEditorPath: String?
    ) {
        try database.write { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: snippetId.uuidString) else {
                throw StorageError.missingSnippet(snippetId.uuidString)
            }
            guard let splitId = sr.splitEditorId else {
                return (try hydrate(sr, db)!, nil)
            }
            let removedPath = try EditorDocumentRecord.fetchOne(db, key: splitId)?.contentFilePath
            try db.execute(
                sql: """
                    UPDATE snippets
                    SET split_editor_id = NULL, split_orientation = NULL, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [now, snippetId.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM editor_documents WHERE id = ?",
                arguments: [splitId]
            )
            let refreshed = try SnippetRecord.fetchOne(db, key: snippetId.uuidString)!
            return (try hydrate(refreshed, db)!, removedPath)
        }
    }

    // MARK: - Language

    /// Updates the main editor's language and detection mode. When `regenerateTitle`
    /// is set and the title is still automatic, the title is recomputed from the new
    /// language (FR-2). Returns the re-hydrated snippet.
    func setMainEditorLanguage(
        snippetId: UUID,
        language: CodeLanguage,
        mode: LanguageMode,
        regenerateTitle: Bool,
        now: Date = Date()
    ) throws -> Snippet {
        try database.write { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: snippetId.uuidString) else {
                throw StorageError.missingSnippet(snippetId.uuidString)
            }
            try db.execute(
                sql:
                    "UPDATE editor_documents SET language = ?, language_mode = ?, updated_at = ? WHERE id = ?",
                arguments: [language.rawValue, mode.rawValue, now, sr.mainEditorId]
            )
            if regenerateTitle, sr.titleSource == SnippetTitleSource.automatic.rawValue {
                let title = try nextTitle(for: language, excluding: snippetId, in: db)
                try db.execute(
                    sql: "UPDATE snippets SET title = ?, updated_at = ? WHERE id = ?",
                    arguments: [title, now, snippetId.uuidString]
                )
            }
            let refreshed = try SnippetRecord.fetchOne(db, key: snippetId.uuidString)!
            return try hydrate(refreshed, db)!
        }
    }

    /// Updates the split editor's language and detection mode. The title is never
    /// touched — the auto title always derives from the main editor (FR-4).
    func setSplitEditorLanguage(
        snippetId: UUID,
        language: CodeLanguage,
        mode: LanguageMode,
        now: Date = Date()
    ) throws -> Snippet {
        try database.write { db in
            guard let sr = try SnippetRecord.fetchOne(db, key: snippetId.uuidString) else {
                throw StorageError.missingSnippet(snippetId.uuidString)
            }
            guard let splitId = sr.splitEditorId else {
                return try hydrate(sr, db)!
            }
            try db.execute(
                sql:
                    "UPDATE editor_documents SET language = ?, language_mode = ?, updated_at = ? WHERE id = ?",
                arguments: [language.rawValue, mode.rawValue, now, splitId]
            )
            let refreshed = try SnippetRecord.fetchOne(db, key: snippetId.uuidString)!
            return try hydrate(refreshed, db)!
        }
    }

    // MARK: - Private

    /// Builds a full `Snippet` from its record, loading the main editor and the
    /// optional split editor. Returns `nil` only if the main editor is missing.
    private func hydrate(_ sr: SnippetRecord, _ db: Database) throws -> Snippet? {
        guard let mainRec = try EditorDocumentRecord.fetchOne(db, key: sr.mainEditorId) else { return nil }
        let split = try sr.splitEditorId
            .flatMap { try EditorDocumentRecord.fetchOne(db, key: $0) }?
            .toModel()
        return sr.toSnippet(mainEditor: mainRec.toModel(), splitEditor: split)
    }

    private func activeCount(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snippets WHERE deleted_at IS NULL") ?? 0
    }

    private func fetchAllSnippets(_ db: Database) throws -> [Snippet] {
        let records =
            try SnippetRecord
            .filter(sql: "deleted_at IS NULL")
            .order(Column("is_pinned").desc, Column("updated_at").desc)
            .fetchAll(db)
        return try records.compactMap { try hydrate($0, db) }
    }

    /// Generates the next auto-title for the given language.
    /// Counts existing non-deleted snippets whose title starts with the language display name,
    /// optionally skipping one snippet (used when retitling that snippet in place).
    private func nextTitle(
        for language: CodeLanguage,
        excluding excludedId: UUID? = nil,
        in db: Database
    ) throws -> String {
        let base = language.displayName
        let count =
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM snippets WHERE title LIKE ? AND deleted_at IS NULL AND id != ?",
                arguments: ["\(base) %", excludedId?.uuidString ?? ""]
            ) ?? 0
        return "\(base) \(count + 1)"
    }

    private func insertDefaultSnippet(_ db: Database) throws -> Snippet {
        let now = Date()
        let editorID = UUID()
        let title = try nextTitle(for: .plainText, in: db)
        let doc = EditorDocument(
            id: editorID,
            contentFilePath: ContentStore.fileName(for: editorID),
            createdAt: now,
            updatedAt: now
        )
        let snippet = Snippet(
            id: UUID(),
            title: title,
            mainEditor: doc,
            createdAt: now,
            updatedAt: now
        )
        try EditorDocumentRecord(from: doc).insert(db)
        try SnippetRecord(from: snippet).insert(db)
        return snippet
    }

    private func fetchFirstSnippet(_ db: Database) throws -> Snippet? {
        guard
            let sr =
                try SnippetRecord
                .filter(sql: "deleted_at IS NULL")
                .order(Column("created_at"))
                .fetchOne(db)
        else { return nil }
        return try hydrate(sr, db)
    }
}
