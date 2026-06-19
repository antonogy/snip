import Foundation

/// Heuristic language detector for the editor.
///
/// Pure and dependency-free: it maps a chunk of text to the most likely
/// `CodeLanguage` by scoring lightweight structural signals. It deliberately
/// does **not** try to parse each language — the goal is "good enough to label
/// a scratch snippet", with `.plainText` as a safe fallback when nothing scores
/// confidently.
public enum LanguageDetector {

    /// Only the leading slice is inspected, so detection stays cheap on large
    /// documents. A few KB is plenty to recognise a language's shape.
    private static let inspectionLimit = 8_192

    /// The winning score must clear this bar; otherwise the text is treated as
    /// prose and reported as `.plainText`.
    private static let confidenceThreshold = 3

    /// Returns the most likely language for `text`, or `.plainText` when the
    /// content is empty or doesn't resemble any supported language.
    public static func detect(_ text: String) -> CodeLanguage {
        let head = String(text.prefix(inspectionLimit))
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plainText }

        // JSON is the one language we can confirm structurally; when the text
        // both looks like and parses as JSON, trust it over any keyword noise.
        if looksLikeJSON(trimmed) { return .json }

        var best: CodeLanguage = .plainText
        var bestScore = 0
        for language in scoredLanguages {
            let score = scoreOf(language, in: trimmed)
            if score > bestScore {
                bestScore = score
                best = language
            }
        }

        return bestScore >= confidenceThreshold ? best : .plainText
    }

    // MARK: - JSON

    private static func looksLikeJSON(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        guard let last = trimmed.last, last == "}" || last == "]" else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: - Keyword/structural scoring

    /// Languages scored by `scoreOf`. JSON is handled separately and Plain Text
    /// is the fallback, so neither appears here. JavaScript precedes TypeScript so
    /// that, on a tie, plain JS wins — TypeScript only overtakes it when a
    /// TS-exclusive signal (types, `interface`, …) pushes its score strictly higher.
    private static let scoredLanguages: [CodeLanguage] = [
        .html, .css, .sql, .swift, .python, .bash, .javascript, .typescript,
    ]

    private static func scoreOf(_ language: CodeLanguage, in text: String) -> Int {
        switch language {
        case .html: return htmlScore(text)
        case .css: return cssScore(text)
        case .sql: return sqlScore(text)
        case .swift: return swiftScore(text)
        case .python: return pythonScore(text)
        case .bash: return bashScore(text)
        case .typescript: return typeScriptScore(text)
        case .javascript: return javaScriptScore(text)
        case .json, .plainText: return 0
        }
    }

    private static func htmlScore(_ text: String) -> Int {
        var score = 0
        let lower = text.lowercased()
        if lower.hasPrefix("<!doctype") || lower.hasPrefix("<html") { score += 4 }
        score += count(#"</[a-zA-Z][\w-]*>"#, in: text) * 2  // closing tags
        score += count(#"<[a-zA-Z][\w-]*(\s[^<>]*)?>"#, in: text)  // opening tags
        if lower.contains("<div") || lower.contains("<span") || lower.contains("<p>") { score += 1 }
        return score
    }

    private static func cssScore(_ text: String) -> Int {
        var score = 0
        score += count(#"[.#]?[\w-]+\s*\{[^}]*\}"#, in: text) * 2  // selector blocks
        score += count(#"[\w-]+\s*:\s*[^;{}]+;"#, in: text)  // declarations
        if contains(#"@(media|import|keyframes|font-face)"#, in: text) { score += 2 }
        if contains(#"#[0-9a-fA-F]{3,8}\b"#, in: text) { score += 1 }  // hex colors
        return score
    }

    private static func sqlScore(_ text: String) -> Int {
        var score = 0
        if contains(#"(?i)^\s*(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE)\b"#, in: text) {
            score += 4
        }
        score += countCaseInsensitive(#"\b(SELECT|FROM|WHERE|JOIN|INSERT|UPDATE|DELETE|VALUES|GROUP\s+BY|ORDER\s+BY)\b"#, in: text)
        return score
    }

    private static func swiftScore(_ text: String) -> Int {
        var score = 0
        if contains(#"\bimport\s+(Foundation|SwiftUI|UIKit|AppKit|Combine)\b"#, in: text) { score += 3 }
        score += count(#"\bfunc\s+\w+\s*\("#, in: text) * 2
        score += count(#"\b(guard|let|var)\b"#, in: text)
        if contains(#"@(MainActor|State|Observable|escaping|Published)\b"#, in: text) { score += 2 }
        if contains(#"->\s*\w"#, in: text) { score += 1 }
        if contains(#"\b(struct|enum|class|protocol|extension)\s+\w+"#, in: text) { score += 1 }
        return score
    }

    private static func pythonScore(_ text: String) -> Int {
        var score = 0
        score += count(#"(?m)^\s*def\s+\w+\s*\("#, in: text) * 2
        score += count(#"(?m)^\s*(import\s+\w+|from\s+[\w.]+\s+import\b)"#, in: text) * 2
        score += count(#"(?m)^\s*(class)\s+\w+"#, in: text)
        if contains(#"(?m)^\s*(if|for|while|elif|else|def|class)\b[^\n]*:\s*$"#, in: text) { score += 2 }
        if contains(#"\bprint\s*\("#, in: text) { score += 1 }
        if contains(#"\b(self|None|True|False|__\w+__)\b"#, in: text) { score += 1 }
        return score
    }

    private static func bashScore(_ text: String) -> Int {
        var score = 0
        if contains(#"^#!.*\b(sh|bash|zsh)\b"#, in: text) { score += 4 }
        if contains(#"\becho\b"#, in: text) { score += 1 }
        score += count(#"\$\{?\w+\}?"#, in: text)  // variable refs
        if contains(#"(?m)^\s*(if|for|while|case)\b.*;\s*(then|do)\b"#, in: text) { score += 2 }
        if contains(#"(?m)\b(fi|done|esac)\s*$"#, in: text) { score += 2 }
        return score
    }

    private static func typeScriptScore(_ text: String) -> Int {
        // TypeScript is JavaScript plus a type system; start from the JS shape
        // and add credit only for TS-exclusive constructs.
        var score = javaScriptScore(text)
        if contains(#"\binterface\s+\w+"#, in: text) { score += 3 }
        if contains(#"\b(type\s+\w+\s*=|enum\s+\w+|namespace\s+\w+)"#, in: text) { score += 3 }
        if contains(#"[:)]\s*(string|number|boolean|void|any|unknown|never)\b"#, in: text) { score += 2 }
        if contains(#"\b(public|private|readonly|implements)\b"#, in: text) { score += 1 }
        if contains(#"\bas\s+\w+"#, in: text) { score += 1 }
        return score
    }

    private static func javaScriptScore(_ text: String) -> Int {
        var score = 0
        score += count(#"\b(const|let)\s+\w+\s*="#, in: text)
        score += count(#"\bfunction\s+\w*\s*\("#, in: text)
        if contains(#"=>\s*[{(]?"#, in: text) { score += 1 }
        if contains(#"\b(require\s*\(|module\.exports|export\s+(default|const|function))"#, in: text) { score += 2 }
        if contains(#"\b(console\.(log|error|warn)|document\.|window\.)"#, in: text) { score += 1 }
        return score
    }

    // MARK: - Regex helpers

    private static func count(_ pattern: String, in text: String) -> Int {
        matchCount(pattern, in: text, options: [])
    }

    private static func countCaseInsensitive(_ pattern: String, in text: String) -> Int {
        matchCount(pattern, in: text, options: [.caseInsensitive])
    }

    private static func contains(_ pattern: String, in text: String) -> Bool {
        matchCount(pattern, in: text, options: [], stopAtFirst: true) > 0
    }

    private static func matchCount(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options,
        stopAtFirst: Bool = false
    ) -> Int {
        // Patterns are compile-time constants; a failed compile is a programmer
        // error, so silently yield no matches rather than trapping at runtime.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if stopAtFirst {
            return regex.firstMatch(in: text, options: [], range: range) != nil ? 1 : 0
        }
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
