import Foundation
import SharedUtilities

/// Manages the flat text files that hold editor content, under `contents/`.
///
/// Metadata stores only the relative filename (`editor_<uuid>.txt`); this type
/// resolves it to an absolute URL and performs atomic reads/writes.
public struct ContentStore: Sendable {
    private let contentsURL: URL

    public init(directories: AppDirectories) {
        self.contentsURL = directories.contentsURL
    }

    /// Relative filename for an editor document's backing file.
    public static func fileName(for editorID: UUID) -> String {
        "editor_\(editorID.uuidString).txt"
    }

    /// Resolves a stored relative path to an absolute URL within `contents/`.
    public func url(forRelativePath relativePath: String) -> URL {
        contentsURL.appendingPathComponent(relativePath)
    }

    /// Reads file content, returning "" when the file does not yet exist.
    public func read(relativePath: String) throws -> String {
        let url = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Atomically writes content to the file at `relativePath`.
    public func write(_ content: String, relativePath: String) throws {
        let url = url(forRelativePath: relativePath)
        try Data(content.utf8).write(to: url, options: .atomic)
    }

    /// Deletes the backing file at `relativePath`, ignoring a missing file.
    public func remove(relativePath: String) throws {
        let url = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
