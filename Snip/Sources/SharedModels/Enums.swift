import Foundation

/// Languages the editor can highlight, detect, and format.
public enum CodeLanguage: String, Codable, CaseIterable, Sendable, Hashable {
    case javascript
    case typescript
    case json
    case html
    case css
    case sql
    case swift
    case python
    case bash
    case plainText

    public var displayName: String {
        switch self {
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .json: return "JSON"
        case .html: return "HTML"
        case .css: return "CSS"
        case .sql: return "SQL"
        case .swift: return "Swift"
        case .python: return "Python"
        case .bash: return "Bash"
        case .plainText: return "Plain Text"
        }
    }
}

/// Whether the language is chosen automatically or pinned by the user.
///
/// A manual selection disables auto detection; emptying the editor returns to `.auto`.
public enum LanguageMode: String, Codable, Sendable, Hashable {
    case auto
    case manual
}

/// How a snippet's title was produced. Manual editing is not supported in v1,
/// but the field exists so the policy can evolve without a migration.
public enum SnippetTitleSource: String, Codable, Sendable, Hashable {
    case automatic
    case manual
}

/// Orientation of the optional second editor.
public enum SplitOrientation: String, Codable, Sendable, Hashable {
    case horizontal
    case vertical
}

/// User-facing appearance preference.
public enum AppearanceMode: String, Codable, Sendable, Hashable {
    case system
    case light
    case dark
}

/// A character range within an editor document.
public struct TextRange: Codable, Sendable, Hashable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// Persisted window geometry, in screen coordinates.
public struct WindowFrame: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Stable identifier for a command-palette command.
public struct CommandId: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}
