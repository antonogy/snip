import Foundation
import SharedModels

/// Failures surfaced by ``CodeFormatter``. Each carries enough context to render
/// a single, actionable, non-modal message in the UI via ``userFacingMessage``.
public enum FormatterError: Error, Equatable, Sendable {
    /// The language has no formatter (currently only `.plainText`).
    case unsupportedLanguage(CodeLanguage)

    /// The required CLI tool could not be found on `PATH`.
    case toolNotFound(tool: String, language: CodeLanguage)

    /// The tool ran but exited non-zero; `message` is its (trimmed) stderr.
    case executionFailed(tool: String, message: String)

    /// The tool did not finish within the allotted time and was terminated.
    case timedOut(tool: String)

    /// A short, user-facing sentence. Tool-not-found cases include an install hint.
    public var userFacingMessage: String {
        switch self {
        case .unsupportedLanguage(let language):
            return "No formatter available for \(language.displayName)."
        case .toolNotFound(let tool, let language):
            return "\(tool) not found — \(Self.installHint(for: tool)) to format \(language.displayName)."
        case .executionFailed(let tool, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(tool) failed to format the code." : "\(tool): \(detail)"
        case .timedOut(let tool):
            return "\(tool) timed out while formatting."
        }
    }

    private static func installHint(for tool: String) -> String {
        switch tool {
        case "sql-formatter": return "install it (npm i -g sql-formatter)"
        case "black": return "install it (pip install black)"
        case "shfmt": return "install it (brew install shfmt)"
        default: return "install it"
        }
    }
}
