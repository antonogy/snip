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
            guard let er = try EditorDocumentRecord.fetchOne(db, key: sr.mainEditorId) else { return nil }
            return sr.toSnippet(mainEditor: er.toModel())
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

    func insertNewSnippet(language: CodeLanguage = .plainText, now: Date = Date()) throws -> Snippet {
        try database.write { db in
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

    func setPinned(id: UUID, isPinned: Bool, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE snippets SET is_pinned = ?, updated_at = ? WHERE id = ?",
                arguments: [isPinned, date, id.uuidString]
            )
        }
    }

    // MARK: - Private

    private func fetchAllSnippets(_ db: Database) throws -> [Snippet] {
        let records = try SnippetRecord
            .filter(sql: "deleted_at IS NULL")
            .order(Column("is_pinned").desc, Column("updated_at").desc)
            .fetchAll(db)
        return try records.compactMap { sr in
            guard let er = try EditorDocumentRecord.fetchOne(db, key: sr.mainEditorId) else { return nil }
            return sr.toSnippet(mainEditor: er.toModel())
        }
    }

    /// Generates the next auto-title for the given language.
    /// Counts existing non-deleted snippets whose title starts with the language display name.
    private func nextTitle(for language: CodeLanguage, in db: Database) throws -> String {
        let base = language.displayName
        let count =
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM snippets WHERE title LIKE ? AND deleted_at IS NULL",
                arguments: ["\(base) %"]
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
        guard let sr = try SnippetRecord
            .filter(sql: "deleted_at IS NULL")
            .order(Column("created_at"))
            .fetchOne(db)
        else { return nil }
        guard let er = try EditorDocumentRecord.fetchOne(db, key: sr.mainEditorId) else { return nil }
        return sr.toSnippet(mainEditor: er.toModel())
    }
}
