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

    /// Reads only the first `maxBytes` of the file, decoded leniently as UTF-8,
    /// returning "" when the file does not exist. Used for the sidebar content
    /// preview so a multi-MB snippet never loads in full just to show 3 lines.
    public func readHead(relativePath: String, maxBytes: Int = 1024) throws -> String {
        let url = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Atomically writes content to the file at `relativePath`.
    public func write(_ content: String, relativePath: String) throws {
        let url = url(forRelativePath: relativePath)
        try Data(content.utf8).write(to: url, options: .atomic)
    }

    /// True when the backing file is missing or zero-length — i.e. no content has
    /// been written. Cheaper than `read`, used by the launch-time empty-snippet purge.
    public func isEmpty(relativePath: String) throws -> Bool {
        let url = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return (values.fileSize ?? 0) == 0
    }

    /// Deletes the backing file at `relativePath`, ignoring a missing file.
    public func remove(relativePath: String) throws {
        let url = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
