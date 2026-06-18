import Foundation
import SharedModels
import SwiftFormat

/// The formatting abstraction (FR-7). Swift is formatted in-process with the
/// `swift-format` library; JavaScript, TypeScript, JSON, CSS, and HTML are
/// formatted in-process by the bundled Prettier (JavaScriptCore) engine; SQL,
/// Python, and Bash are piped through their canonical CLI. Plain Text has no
/// formatter.
///
/// `format(_:language:)` is `nonisolated async`, so awaiting it from `@MainActor`
/// code automatically hops off the main actor: the swift-format / Prettier CPU
/// work and the CLI process IO all run on a background executor.
public struct CodeFormatter: Sendable {
    public init() {}

    /// Returns `text` formatted for `language`, or throws a ``FormatterError``.
    public func format(_ text: String, language: CodeLanguage) async throws -> String {
        switch language {
        case .plainText:
            throw FormatterError.unsupportedLanguage(.plainText)
        case .swift:
            return try formatSwift(text)
        case .javascript, .typescript, .json, .css, .html:
            return try PrettierFormatting.format(text, language: language)
        default:
            guard let spec = ProcessFormatter.commandSpec(for: language) else {
                throw FormatterError.unsupportedLanguage(language)
            }
            return try await ProcessFormatter.runAsync(spec: spec, input: text, language: language)
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
