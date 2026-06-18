import Foundation
import SharedModels
import SharedUtilities
import Storage
import Testing

private func makeTempDirectories() throws -> AppDirectories {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("snip-tests-\(UUID().uuidString)", isDirectory: true)
    return try AppDirectories(root: root)
}

@Test func migrationsCreateExpectedSchema() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    // Throws if any expected table is missing.
    try stack.verifySchema()
    #expect(FileManager.default.fileExists(atPath: directories.databaseURL.path))
}

@Test func openingExistingDatabaseReMigratesCleanly() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    _ = try StorageStack(directories: directories)
    // Re-opening the same container (a relaunch) must not fail or duplicate work.
    let reopened = try StorageStack(directories: AppDirectories(root: directories.root))
    try reopened.verifySchema()
}

@Test func settingsDefaultWhenAbsentAndRoundTrip() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    #expect(stack.loadSettings() == .default)

    var settings = Settings.default
    settings.appearanceMode = .dark
    settings.expirationDays = 14
    settings.wordWrapEnabled = false
    try stack.saveSettings(settings)

    #expect(stack.loadSettings() == settings)
}

@Test func appStateRoundTrip() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    #expect(stack.loadAppState() == .default)

    var state = AppState.default
    state.sidebarVisible = false
    state.sidebarWidth = 333
    state.selectedSnippetId = UUID()
    state.windowFrame = WindowFrame(x: 10, y: 20, width: 800, height: 600)
    state.commandPaletteRecentCommands = ["new.snippet", "format.code"]
    try stack.saveAppState(state)

    #expect(stack.loadAppState() == state)
}

@Test func stateSurvivesSimulatedRelaunch() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    do {
        let stack = try StorageStack(directories: directories)
        var state = AppState.default
        state.sidebarWidth = 410
        state.windowFrame = WindowFrame(x: 5, y: 5, width: 1024, height: 768)
        try stack.saveAppState(state)

        var settings = Settings.default
        settings.appearanceMode = .light
        try stack.saveSettings(settings)
    }

    // Fresh stack over the same directory = relaunch.
    let relaunched = try StorageStack(directories: AppDirectories(root: directories.root))
    let restored = relaunched.restore()
    #expect(restored.appState.sidebarWidth == 410)
    #expect(restored.appState.windowFrame == WindowFrame(x: 5, y: 5, width: 1024, height: 768))
    #expect(restored.settings.appearanceMode == .light)
}

@Test func corruptConfigFallsBackToDefaults() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    try Data("this is not json{".utf8).write(to: directories.settingsURL)
    let stack = try StorageStack(directories: directories)
    // Must not crash; reliability requires falling back rather than failing.
    #expect(stack.loadSettings() == .default)
}

@Test func contentStoreReadWriteRoundTrip() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let store = ContentStore(directories: directories)
    let relativePath = ContentStore.fileName(for: UUID())

    #expect(try store.read(relativePath: relativePath) == "")
    try store.write("let answer = 42\n", relativePath: relativePath)
    #expect(try store.read(relativePath: relativePath) == "let answer = 42\n")
}

@Test func bootstrapCreatesDefaultSnippet() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let (snippet, content) = try stack.loadOrBootstrap()

    #expect(!snippet.id.uuidString.isEmpty)
    #expect(content == "")
    #expect(snippet.title == "Plain Text 1")
    #expect(!snippet.mainEditor.contentFilePath.isEmpty)
}

@Test func bootstrapIsIdempotent() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let (first, _) = try stack.loadOrBootstrap()
    let (second, _) = try stack.loadOrBootstrap()

    #expect(first.id == second.id)
    #expect(first.mainEditor.id == second.mainEditor.id)
}

@Test func editorContentSurvivesRelaunch() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let content = "func hello() {\n    print(\"world\")\n}\n"

    do {
        let stack = try StorageStack(directories: directories)
        let (snippet, _) = try stack.loadOrBootstrap()
        try stack.saveEditorContent(content, for: snippet.mainEditor)
    }

    // Fresh stack over the same directory = relaunch.
    let relaunched = try StorageStack(directories: AppDirectories(root: directories.root))
    let (_, restoredContent) = try relaunched.loadOrBootstrap()
    #expect(restoredContent == content)
}

// MARK: - Milestone 4: Multi-snippet tests

@Test func listSnippetsReturnsAll() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    _ = try stack.loadOrBootstrap()  // creates first snippet
    _ = try stack.createSnippet()  // second
    _ = try stack.createSnippet()  // third

    let list = try stack.listSnippets()
    #expect(list.count == 3)
    // Verify newest-first ordering within unpinned group.
    #expect(list[0].updatedAt >= list[1].updatedAt)
    #expect(list[1].updatedAt >= list[2].updatedAt)
}

@Test func createSnippetGeneratesTitle() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let first = try stack.createSnippet()
    let second = try stack.createSnippet()

    #expect(first.title == "Plain Text 1")
    #expect(second.title == "Plain Text 2")
}

@Test func deleteSnippetHidesFromList() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    try stack.deleteSnippet(id: snippet.id)

    let list = try stack.listSnippets()
    #expect(!list.contains(where: { $0.id == snippet.id }))
}

@Test func togglePinReordersSnippets() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let first = try stack.createSnippet()
    _ = try stack.createSnippet()  // second; newer, would be at index 0 unpinned

    // Pin the older snippet — it should jump to the top.
    try stack.setSnippetPinned(id: first.id, isPinned: true)

    let list = try stack.listSnippets()
    #expect(list.first?.id == first.id)
    #expect(list.first?.isPinned == true)
}

@Test func softDeleteCreatesRecoveryItem() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    try stack.deleteSnippet(id: snippet.id)

    let count = try stack.database.read { db in
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM recovery_items WHERE snippet_id = ?",
            arguments: [snippet.id.uuidString]
        ) ?? 0
    }
    #expect(count == 1)
}

// MARK: - FR-1: Empty-snippet purge on launch

@Test func purgeRemovesEmptySnippetAndItsFile() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    let filePath = ContentStore(directories: directories)
        .url(forRelativePath: snippet.mainEditor.contentFilePath).path

    let purged = try stack.purgeEmptySnippets()
    #expect(purged == 1)
    let list = try stack.listSnippets()
    #expect(!list.contains(where: { $0.id == snippet.id }))
    #expect(!FileManager.default.fileExists(atPath: filePath))
}

@Test func purgeKeepsSnippetWithContent() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    try stack.saveEditorContent("let x = 1\n", for: snippet.mainEditor)

    let purged = try stack.purgeEmptySnippets()
    #expect(purged == 0)
    let list = try stack.listSnippets()
    #expect(list.contains(where: { $0.id == snippet.id }))
}

@Test func purgeKeepsSnippetWhenOnlySplitHasContent() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    let withSplit = try stack.setSplit(snippetId: snippet.id, orientation: .horizontal)
    let split = try #require(withSplit.splitEditor)
    // Main editor stays empty; only the split has content.
    try stack.saveEditorContent("SELECT 1;\n", for: split)

    let purged = try stack.purgeEmptySnippets()
    #expect(purged == 0)
    let list = try stack.listSnippets()
    #expect(list.contains(where: { $0.id == snippet.id }))
}

@Test func purgeBypassesRecovery() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()

    try stack.purgeEmptySnippets()

    // Unlike soft-delete, the permanent purge leaves no recovery row and no
    // editor_documents rows behind.
    let recoveryCount = try stack.database.read { db in
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM recovery_items WHERE snippet_id = ?",
            arguments: [snippet.id.uuidString]
        ) ?? 0
    }
    #expect(recoveryCount == 0)

    let editorExists = try stack.database.read { db in
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM editor_documents WHERE id = ?)",
            arguments: [snippet.mainEditor.id.uuidString]
        ) ?? false
    }
    #expect(editorExists == false)
}

@Test func purgePoolsMultipleEmptiesAndReportsCount() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let kept = try stack.createSnippet()
    try stack.saveEditorContent("keep me\n", for: kept.mainEditor)
    _ = try stack.createSnippet()  // empty
    _ = try stack.createSnippet()  // empty

    let purged = try stack.purgeEmptySnippets()
    #expect(purged == 2)

    let remaining = try stack.listSnippets()
    #expect(remaining.count == 1)
    #expect(remaining.first?.id == kept.id)
}

// MARK: - Milestone 5: Split editor tests

@Test func setSplitCreatesEmptyEditorInheritingLanguage() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()

    let updated = try stack.setSplit(snippetId: snippet.id, orientation: .horizontal)
    let split = try #require(updated.splitEditor)

    #expect(updated.splitOrientation == .horizontal)
    #expect(split.id != updated.mainEditor.id)
    #expect(split.language == updated.mainEditor.language)
    // Split content starts empty, with a backing file present.
    #expect(try stack.loadSnippetContent(for: split) == "")
}

@Test func setSplitTwiceOnlyReorients() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()

    let first = try stack.setSplit(snippetId: snippet.id, orientation: .horizontal)
    let firstSplitId = try #require(first.splitEditor).id

    let second = try stack.setSplit(snippetId: snippet.id, orientation: .vertical)
    // Same split editor, only the orientation changed — enforces "one split only".
    #expect(second.splitEditor?.id == firstSplitId)
    #expect(second.splitOrientation == .vertical)

    let editorCount = try stack.database.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM editor_documents") ?? 0
    }
    #expect(editorCount == 2)  // main + one split
}

@Test func splitContentAndOrientationSurviveRelaunch() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let splitContent = "SELECT * FROM users;\n"
    let snippetId: UUID

    do {
        let stack = try StorageStack(directories: directories)
        let snippet = try stack.createSnippet()
        snippetId = snippet.id
        let updated = try stack.setSplit(snippetId: snippet.id, orientation: .vertical)
        let split = try #require(updated.splitEditor)
        try stack.saveEditorContent(splitContent, for: split)
    }

    // Fresh stack over the same directory = relaunch.
    let relaunched = try StorageStack(directories: AppDirectories(root: directories.root))
    let restored = try #require(relaunched.listSnippets().first(where: { $0.id == snippetId }))
    let split = try #require(restored.splitEditor)

    #expect(restored.splitOrientation == .vertical)
    #expect(try relaunched.loadSnippetContent(for: split) == splitContent)
}

@Test func closeSplitClearsReferencesAndDeletesEditor() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    let withSplit = try stack.setSplit(snippetId: snippet.id, orientation: .horizontal)
    let split = try #require(withSplit.splitEditor)
    let splitFilePath = ContentStore(directories: directories).url(forRelativePath: split.contentFilePath)
        .path

    let closed = try stack.closeSplit(snippetId: snippet.id)
    #expect(closed.splitEditor == nil)
    #expect(closed.splitOrientation == nil)

    // The orphaned editor row and its content file are gone.
    let exists = try stack.database.read { db in
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM editor_documents WHERE id = ?)",
            arguments: [split.id.uuidString]
        ) ?? false
    }
    #expect(exists == false)
    #expect(!FileManager.default.fileExists(atPath: splitFilePath))
}

// MARK: - Milestone 6: Language detection persistence

@Test func setMainLanguageUpdatesLanguageAndRetitles() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    #expect(snippet.title == "Plain Text 1")

    let updated = try stack.setMainLanguage(snippetId: snippet.id, language: .swift, mode: .auto)
    #expect(updated.mainEditor.language == .swift)
    #expect(updated.mainEditor.languageMode == .auto)
    // Automatic title follows the detected language (FR-2).
    #expect(updated.title == "Swift 1")
}

@Test func setMainLanguageManualModePersists() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()

    _ = try stack.setMainLanguage(snippetId: snippet.id, language: .python, mode: .manual)

    // Fresh stack over the same directory = relaunch.
    let relaunched = try StorageStack(directories: AppDirectories(root: directories.root))
    let restored = try #require(relaunched.listSnippets().first(where: { $0.id == snippet.id }))
    #expect(restored.mainEditor.language == .python)
    #expect(restored.mainEditor.languageMode == .manual)
    #expect(restored.title == "Python 1")
}

@Test func setSplitLanguageDoesNotAffectTitle() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    let withSplit = try stack.setSplit(snippetId: snippet.id, orientation: .horizontal)
    let originalTitle = withSplit.title

    let updated = try stack.setSplitLanguage(snippetId: snippet.id, language: .json, mode: .manual)
    #expect(updated.splitEditor?.language == .json)
    #expect(updated.splitEditor?.languageMode == .manual)
    // Main editor and title are untouched — auto title derives from main only (FR-4).
    #expect(updated.mainEditor.language == .plainText)
    #expect(updated.title == originalTitle)
}

@Test func retitlingNumbersIndependentlyPerLanguage() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let a = try stack.createSnippet()  // Plain Text 1
    let b = try stack.createSnippet()  // Plain Text 2

    let aSwift = try stack.setMainLanguage(snippetId: a.id, language: .swift, mode: .auto)
    let bSwift = try stack.setMainLanguage(snippetId: b.id, language: .swift, mode: .auto)
    #expect(aSwift.title == "Swift 1")
    #expect(bSwift.title == "Swift 2")
}

// MARK: - Milestone 10: Expiration & Recovery

/// Backdates a snippet's and its main editor's `updated_at` so it reads as stale.
private func backdate(_ stack: StorageStack, snippet: Snippet, to date: Date) throws {
    try stack.database.write { db in
        try db.execute(
            sql: "UPDATE snippets SET updated_at = ? WHERE id = ?",
            arguments: [date, snippet.id.uuidString])
        try db.execute(
            sql: "UPDATE editor_documents SET updated_at = ? WHERE id = ?",
            arguments: [date, snippet.mainEditor.id.uuidString])
    }
}

private func recoveryCount(_ stack: StorageStack, snippetId: UUID) throws -> Int {
    try stack.database.read { db in
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM recovery_items WHERE snippet_id = ?",
            arguments: [snippetId.uuidString]
        ) ?? 0
    }
}

@Test func expireStaleSnippetsMovesUnpinnedToRecovery() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    try backdate(stack, snippet: snippet, to: Date().addingTimeInterval(-100 * 86_400))

    let expired = try stack.expireStaleSnippets(expirationDays: 7, gracePeriodDays: 30)
    #expect(expired == 1)
    #expect(!(try stack.listSnippets()).contains(where: { $0.id == snippet.id }))
    #expect(try recoveryCount(stack, snippetId: snippet.id) == 1)
}

@Test func expireStaleSnippetsKeepsPinnedAndFresh() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let pinned = try stack.createSnippet()
    let fresh = try stack.createSnippet()
    // Pin first, then backdate: pinned snippets are exempt regardless of age.
    try stack.setSnippetPinned(id: pinned.id, isPinned: true)
    try backdate(stack, snippet: pinned, to: Date().addingTimeInterval(-100 * 86_400))

    let expired = try stack.expireStaleSnippets(expirationDays: 7, gracePeriodDays: 30)
    #expect(expired == 0)
    let list = try stack.listSnippets()
    #expect(list.contains(where: { $0.id == pinned.id }))
    #expect(list.contains(where: { $0.id == fresh.id }))
}

@Test func restoreSnippetReturnsItToListAndClearsRecovery() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    try stack.deleteSnippet(id: snippet.id)

    let restored = try stack.restoreSnippet(id: snippet.id)
    #expect(restored.id == snippet.id)
    #expect(restored.deletedAt == nil)
    #expect((try stack.listSnippets()).contains(where: { $0.id == snippet.id }))
    #expect(try recoveryCount(stack, snippetId: snippet.id) == 0)
}

@Test func purgeExpiredRecoveryItemsRemovesPastRetention() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let stale = try stack.createSnippet()
    let recent = try stack.createSnippet()
    try stack.saveEditorContent("keep me\n", for: stale.mainEditor)
    let stalePath = ContentStore(directories: directories)
        .url(forRelativePath: stale.mainEditor.contentFilePath).path

    try stack.deleteSnippet(id: stale.id, gracePeriodDays: 30)
    try stack.deleteSnippet(id: recent.id, gracePeriodDays: 30)
    // Push the stale item's retention window into the past.
    try stack.database.write { db in
        try db.execute(
            sql: "UPDATE recovery_items SET purge_after = ? WHERE snippet_id = ?",
            arguments: [Date().addingTimeInterval(-86_400), stale.id.uuidString])
    }

    let purged = try stack.purgeExpiredRecoveryItems()
    #expect(purged == 1)
    #expect(!FileManager.default.fileExists(atPath: stalePath))
    #expect(try recoveryCount(stack, snippetId: stale.id) == 0)
    #expect(try recoveryCount(stack, snippetId: recent.id) == 1)

    let editorExists = try stack.database.read { db in
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM editor_documents WHERE id = ?)",
            arguments: [stale.mainEditor.id.uuidString]
        ) ?? false
    }
    #expect(editorExists == false)
}

@Test func listRecoveryItemsReturnsDeletedNewestFirst() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }

    let stack = try StorageStack(directories: directories)
    let older = try stack.createSnippet()
    let newer = try stack.createSnippet()
    try stack.deleteSnippet(id: older.id)
    try stack.deleteSnippet(id: newer.id)
    // Make the ordering deterministic regardless of clock resolution.
    try stack.database.write { db in
        try db.execute(
            sql: "UPDATE recovery_items SET deleted_at = ? WHERE snippet_id = ?",
            arguments: [Date().addingTimeInterval(-3_600), older.id.uuidString])
    }

    let items = try stack.listRecoveryItems()
    #expect(items.count == 2)
    #expect(items.first?.snippetId == newer.id)
    #expect(items.last?.snippetId == older.id)
}
