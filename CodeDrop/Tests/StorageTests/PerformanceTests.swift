import Foundation
import SharedModels
import SharedUtilities
import Storage
import Testing

/// Performance benchmarks for the storage layer.
///
/// Thresholds are deliberately generous to avoid CI flakiness while still
/// catching regressions. The targets below correspond to the budget each
/// operation is allowed to consume within the overall startup / switching
/// targets from §10 of the implementation plan:
///
///   Startup < 500 ms perceived   →  storage-only portion must be well under 200 ms
///   Snippet switching < 100 ms   →  load + flush must be well under 50 ms each
///   Autosave < 16 ms typing lag  →  write path must be negligible (debounced anyway)
private func makeTempDirectories() throws -> AppDirectories {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("snip-perf-\(UUID().uuidString)", isDirectory: true)
    return try AppDirectories(root: root)
}

// MARK: — Startup: storage init

/// First launch opens the DB, creates schema, and writes the migrations table.
@Test func storageStackFirstOpenIsUnder500ms() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let start = ContinuousClock.now
    _ = try StorageStack(directories: directories)
    #expect(ContinuousClock.now - start < .milliseconds(500))
}

/// Subsequent launches (the common case) skip migrations — must be very fast.
@Test func storageStackSubsequentOpenIsUnder100ms() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    _ = try StorageStack(directories: directories)
    let start = ContinuousClock.now
    _ = try StorageStack(directories: AppDirectories(root: directories.root))
    #expect(ContinuousClock.now - start < .milliseconds(100))
}

// MARK: — Startup: snippet list refresh

/// Listing all snippets at the 100-snippet cap must fit comfortably in the
/// startup budget. Threshold is set at 500 ms to remain stable under parallel
/// CI load while still catching regressions that add per-snippet blocking work.
@Test func listSnippetsAtCapIsUnder500ms() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let stack = try StorageStack(directories: directories)
    for _ in 0..<Limits.maxActiveSnippets {
        _ = try stack.createSnippet()
    }
    let start = ContinuousClock.now
    _ = try stack.listSnippets()
    #expect(ContinuousClock.now - start < .milliseconds(500))
}

// MARK: — Startup: launch-time purge

/// The worst-case purge (every snippet empty, e.g. a crash loop) must use a
/// single write transaction. Before the batching fix, 100 separate commits at
/// ~10 ms each = ~1000 ms; the 1500 ms ceiling catches a regression to that
/// pattern even under parallel CI load while leaving plenty of room for the
/// 100 file-size checks and 100 file deletions that run regardless.
@Test func purgeEmptySnippetsAtCapIsUnder1500ms() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let stack = try StorageStack(directories: directories)
    for _ in 0..<Limits.maxActiveSnippets {
        _ = try stack.createSnippet()
    }
    let start = ContinuousClock.now
    let purged = try stack.purgeEmptySnippets()
    let elapsed = ContinuousClock.now - start
    #expect(purged == Limits.maxActiveSnippets)
    #expect(elapsed < .milliseconds(1500))
}

// MARK: — Snippet switching: content load

/// Loading a typical snippet (~6 KB, ~500 lines) must leave the main thread
/// free for the 100 ms switching target.
@Test func loadSnippetContentIsUnder50ms() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    let text = String(repeating: "let x = 42\n", count: 500)  // ~6 KB
    try stack.saveEditorContent(text, for: snippet.mainEditor)
    let start = ContinuousClock.now
    _ = try stack.loadSnippetContent(for: snippet.mainEditor)
    #expect(ContinuousClock.now - start < .milliseconds(50))
}

// MARK: — Autosave throughput

/// A single atomic write + DB timestamp bump must stay negligible relative to
/// the 1-second debounce window that precedes it.
@Test func saveEditorContentIsUnder50ms() throws {
    let directories = try makeTempDirectories()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let stack = try StorageStack(directories: directories)
    let snippet = try stack.createSnippet()
    let text = String(repeating: "func foo() { }\n", count: 500)  // ~8 KB
    let start = ContinuousClock.now
    try stack.saveEditorContent(text, for: snippet.mainEditor)
    #expect(ContinuousClock.now - start < .milliseconds(50))
}
