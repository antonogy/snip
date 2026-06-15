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
