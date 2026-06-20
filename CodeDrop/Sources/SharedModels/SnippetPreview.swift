import Foundation

/// Derives the content preview shown in the sidebar card from an editor's text.
///
/// The sidebar shows the first few non-empty lines of the snippet's content
/// instead of a generated title. These helpers are pure so they can be unit
/// tested and reused for the single-line Recovery label.
public enum SnippetPreview {
    /// The first `maxLines` non-empty lines of `text`, each trimmed of trailing
    /// whitespace. Blank and whitespace-only lines are skipped. Handles both LF
    /// and CRLF line endings.
    public static func previewLines(from text: String, maxLines: Int = 3) -> [String] {
        guard maxLines > 0 else { return [] }
        var result: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            result.append(line)
            if result.count == maxLines { break }
        }
        return result
    }

    /// The first non-empty trimmed line of `text`, or "" when there is none.
    /// Used as the single-line label retained for Recovery.
    public static func previewTitle(from text: String) -> String {
        previewLines(from: text, maxLines: 1).first ?? ""
    }
}
