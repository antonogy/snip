import Foundation
import SharedModels
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// Parses editor text with tree-sitter and returns the colored spans for it.
///
/// An `actor` because tree-sitter's parser/tree objects wrap C state and are
/// **not** `Sendable`. Confining them here means only a plain `String` goes in
/// and a `Sendable` `[HighlightSpan]` comes out — the non-`Sendable` machinery
/// never crosses an isolation boundary.
///
/// Highlighting runs through `SwiftTreeSitterLayer`, which parses the root
/// grammar *and* any injected sub-languages (Markdown fenced code, the inline
/// Markdown grammar, `<script>`/`<style>` inside HTML), so nested code is colored
/// too. The language of each injection is resolved through `Grammar`'s shared
/// configuration table.
///
/// Parsing is done from scratch on every call rather than incrementally: a
/// correct incremental re-parse requires feeding tree-sitter the exact edit
/// deltas, and getting that wrong silently corrupts the tree. Snippets are small
/// and the call site is debounced, so a full re-parse is both simpler and safe.
public actor SyntaxHighlighter {

    /// Root grammar configuration for the current language, or nil when idle
    /// (`.plainText`, a format-only language, or a failed setup).
    private var rootConfig: LanguageConfiguration?

    /// Resolves injected languages to their configurations. Capped depth keeps a
    /// pathological nesting chain from recursing without bound.
    private let layerConfiguration = LanguageLayer.Configuration(
        maximumLanguageDepth: 4,
        languageProvider: { Grammar.injectedConfiguration(named: $0) }
    )

    public init() {}

    /// Configures the highlighter for `language`. On `.plainText`, a format-only
    /// language, or any failure, the highlighter goes idle and `highlights(for:)`
    /// returns no spans.
    public func setLanguage(_ language: CodeLanguage) {
        rootConfig = Grammar.configuration(for: language)
    }

    /// The colored spans for `text` under the current language. Empty when the
    /// highlighter is idle or the text is empty.
    public func highlights(for text: String) -> [HighlightSpan] {
        guard let rootConfig, !text.isEmpty else { return [] }

        do {
            let layer = try LanguageLayer(
                languageConfig: rootConfig, configuration: layerConfiguration)
            layer.replaceContent(with: text)

            let content = LanguageLayer.Content(string: text)
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let namedRanges = try layer.highlights(in: fullRange, provider: content.textProvider)

            var spans: [HighlightSpan] = []
            spans.reserveCapacity(namedRanges.count)
            for named in namedRanges {
                let token = HighlightToken(capture: named.name)
                guard token != .plain else { continue }
                spans.append(HighlightSpan(range: named.range, token: token))
            }

            // Order overlapping spans widest-first (by start, then longest) so the
            // editor — which applies foreground colors in array order, last write
            // winning — paints an outer span first and lets a narrower, deeper one
            // (e.g. an injected language's token inside a Markdown code fence)
            // override it.
            spans.sort {
                $0.range.location != $1.range.location
                    ? $0.range.location < $1.range.location
                    : $0.range.length > $1.range.length
            }
            return spans
        } catch {
            return []
        }
    }
}
