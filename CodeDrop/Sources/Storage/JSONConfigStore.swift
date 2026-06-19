import Foundation
import SharedUtilities

/// Reads and writes a single `Codable` value to a JSON file.
///
/// Reads never throw: a missing or corrupt file falls back to a caller-supplied
/// default (corruption is logged), because losing user content to a malformed
/// config file would violate the reliability requirement. Writes are atomic.
public struct JSONConfigStore: Sendable {
    private let log = AppLog.make("storage.config")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init() {}

    /// Loads the value at `url`, returning `fallback` if the file is absent or unreadable.
    public func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            log.error(
                "Failed to read \(url.lastPathComponent, privacy: .public); using defaults: \(error.localizedDescription, privacy: .public)"
            )
            return fallback
        }
    }

    /// Atomically writes `value` to `url`.
    public func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
