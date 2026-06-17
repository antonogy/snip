import Foundation
import SharedModels
import SwiftTreeSitter

/// Parses editor text with tree-sitter and returns the colored spans for it.
///
/// An `actor` because tree-sitter's `Parser`/`Query`/tree objects are reference
/// types that wrap C state and are **not** `Sendable`. Confining them here means
/// only a plain `String` goes in and a `Sendable` `[HighlightSpan]` comes out —
/// the non-`Sendable` machinery never crosses an isolation boundary.
///
/// Parsing is done from scratch on every call rather than incrementally: a
/// correct incremental re-parse requires feeding tree-sitter the exact edit
/// deltas, and getting that wrong silently corrupts the tree. Snippets are
/// small and the call site is debounced, so a full re-parse is both simpler and
/// safe. Incremental parsing can be added later behind this same interface.
public actor SyntaxHighlighter {
    private var language: CodeLanguage = .plainText
    private var parser: Parser?
    private var query: Query?

    public init() {}

    /// Configures the highlighter for `language`. Rebuilds the parser and
    /// compiles the highlight query; on `.plainText` (or any failure) the
    /// highlighter goes idle and `highlights(for:)` returns no spans.
    public func setLanguage(_ language: CodeLanguage) {
        self.language = language

        guard
            let tsLanguage = Grammar.language(for: language),
            let source = Grammar.highlightQuerySource(for: language)
        else {
            parser = nil
            query = nil
            return
        }

        do {
            let parser = Parser()
            try parser.setLanguage(tsLanguage)
            self.parser = parser
            self.query = try Query(language: tsLanguage, data: Data(source.utf8))
        } catch {
            parser = nil
            query = nil
        }
    }

    /// The colored spans for `text` under the current language. Empty when the
    /// highlighter is idle (`.plainText` / failed setup) or the text is empty.
    public func highlights(for text: String) -> [HighlightSpan] {
        guard let parser, let query, !text.isEmpty else { return [] }
        guard let tree = parser.parse(tree: nil as Tree?, string: text) else { return [] }

        // Resolve predicates (e.g. `#match?`, `#eq?`) against the text so that
        // patterns like "(identifier) @constant (#match? ... ^[A-Z_]+$)" only
        // match where they should, instead of capturing every identifier.
        let context = Predicate.Context(string: text)
        var spans: [HighlightSpan] = []
        for match in query.execute(in: tree).resolve(with: context) {
            for capture in match.captures {
                guard let name = capture.name else { continue }
                let token = HighlightToken(capture: name)
                guard token != .plain else { continue }
                spans.append(HighlightSpan(range: capture.range, token: token))
            }
        }
        return spans
    }
}
