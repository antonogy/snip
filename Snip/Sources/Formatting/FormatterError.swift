import Foundation
import SharedModels

/// Failures surfaced by ``CodeFormatter``. Each carries enough context to render
/// a single, actionable, non-modal message in the UI via ``userFacingMessage``.
public enum FormatterError: Error, Equatable, Sendable {
    /// The language has no built-in formatter (SQL, Python, Bash, Plain Text).
    case unsupportedLanguage(CodeLanguage)

    /// The formatter ran but failed; `message` is its (trimmed) diagnostic.
    case executionFailed(tool: String, message: String)

    /// A short, user-facing sentence.
    public var userFacingMessage: String {
        switch self {
        case .unsupportedLanguage(let language):
            return "No formatter available for \(language.displayName)."
        case .executionFailed(let tool, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(tool) failed to format the code." : "\(tool): \(detail)"
        }
    }
}
