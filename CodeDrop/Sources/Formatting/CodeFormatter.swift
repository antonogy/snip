import Foundation
import SharedModels
import SwiftFormat

/// The formatting abstraction (FR-7). Swift is formatted in-process with the
/// `swift-format` library; JavaScript, TypeScript, JSON, CSS, and HTML are
/// formatted in-process by the bundled Prettier (JavaScriptCore) engine. Every
/// formatter is built in; a language without one (SQL, Python, Bash, Plain Text)
/// simply has the feature disabled.
///
/// `format(_:language:)` is `nonisolated async`, so awaiting it from `@MainActor`
/// code automatically hops off the main actor: the swift-format / Prettier CPU
/// work runs on a background executor.
public struct CodeFormatter: Sendable {
    public init() {}

    /// Whether a built-in formatter exists for `language`. Drives whether the
    /// "Format Code" feature is enabled; languages without a formatter are
    /// silently unavailable.
    public func supports(_ language: CodeLanguage) -> Bool {
        switch language {
        case .swift, .javascript, .typescript, .json, .css, .html,
            .markdown, .yaml, .php, .graphql, .flow, .vue, .angular:
            return true
        case .sql, .python, .bash, .plainText:
            return false
        }
    }

    /// Returns `text` formatted for `language`, or throws a ``FormatterError``.
    /// Languages without a built-in formatter throw ``FormatterError/unsupportedLanguage(_:)``.
    public func format(_ text: String, language: CodeLanguage) async throws -> String {
        switch language {
        case .swift:
            return try formatSwift(text)
        case .javascript, .typescript, .json, .css, .html,
            .markdown, .yaml, .php, .graphql, .flow, .vue, .angular:
            return try PrettierFormatting.format(text, language: language)
        case .sql, .python, .bash, .plainText:
            throw FormatterError.unsupportedLanguage(language)
        }
    }

    /// Formats Swift source with the bundled `swift-format` library using its
    /// default configuration. `SwiftFormatter`/`Configuration` are not `Sendable`,
    /// so they are created and used entirely within this synchronous call and
    /// never cross a task or actor boundary.
    private func formatSwift(_ text: String) throws -> String {
        let formatter = SwiftFormatter(configuration: Configuration())
        var output = ""
        do {
            try formatter.format(source: text, assumingFileURL: nil, selection: .infinite, to: &output)
        } catch {
            throw FormatterError.executionFailed(tool: "swift-format", message: error.localizedDescription)
        }
        return output
    }
}
