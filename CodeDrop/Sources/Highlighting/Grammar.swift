import Foundation
import SharedModels
import SwiftTreeSitter
import TreeSitterAngular
import TreeSitterBash
import TreeSitterCSS
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterPHP
import TreeSitterPython
import TreeSitterSql
import TreeSitterSwift
import TreeSitterTypeScript
import TreeSitterYAML

/// Bridges CodeDrop's `CodeLanguage` to tree-sitter grammars and their bundled
/// highlight / injection queries. Everything tree-sitter-specific is confined
/// here so the rest of the module (and `SharedModels`) never sees a grammar
/// pointer.
///
/// The grammar table is keyed by string name rather than by `CodeLanguage`
/// because those names double as tree-sitter *injection* language names: a
/// fenced ```` ```js ```` block in Markdown, or a `<script>` inside HTML,
/// resolves through the very same table so the embedded language highlights too
/// (see ``injectedConfiguration(named:)``). It therefore holds entries with no
/// `CodeLanguage` of their own — e.g. Markdown's inline sub-grammar.
enum Grammar {

    private struct Spec: Sendable {
        let language: @Sendable () -> OpaquePointer?
        let queryFolder: String
    }

    private static let specs: [String: Spec] = [
        "javascript": Spec(language: { tree_sitter_javascript() }, queryFolder: "javascript"),
        "typescript": Spec(language: { tree_sitter_typescript() }, queryFolder: "typescript"),
        "json": Spec(language: { tree_sitter_json() }, queryFolder: "json"),
        "html": Spec(language: { tree_sitter_html() }, queryFolder: "html"),
        "css": Spec(language: { tree_sitter_css() }, queryFolder: "css"),
        "python": Spec(language: { tree_sitter_python() }, queryFolder: "python"),
        "bash": Spec(language: { tree_sitter_bash() }, queryFolder: "bash"),
        "swift": Spec(language: { tree_sitter_swift() }, queryFolder: "swift"),
        "sql": Spec(language: { tree_sitter_sql() }, queryFolder: "sql"),
        "php": Spec(language: { tree_sitter_php() }, queryFolder: "php"),
        "yaml": Spec(language: { tree_sitter_yaml() }, queryFolder: "yaml"),
        "markdown": Spec(language: { tree_sitter_markdown() }, queryFolder: "markdown"),
        "markdown_inline": Spec(
            language: { tree_sitter_markdown_inline() }, queryFolder: "markdown_inline"),
        "angular": Spec(language: { tree_sitter_angular() }, queryFolder: "angular"),
    ]

    /// Grammar key for a `CodeLanguage`, or nil when it has no highlighting
    /// grammar: GraphQL and Vue are format-only (no SwiftPM grammar), Plain Text
    /// never highlights. Flow reuses the JavaScript grammar.
    private static func specKey(for language: CodeLanguage) -> String? {
        switch language {
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .json: return "json"
        case .html: return "html"
        case .css: return "css"
        case .python: return "python"
        case .bash: return "bash"
        case .swift: return "swift"
        case .sql: return "sql"
        case .php: return "php"
        case .yaml: return "yaml"
        case .markdown: return "markdown"
        case .angular: return "angular"
        case .flow: return "javascript"
        case .graphql, .vue, .plainText: return nil
        }
    }

    /// Normalises a tree-sitter injection language name (any token from a code
    /// fence info string or a grammar `#set!`) to a grammar key, or nil when we
    /// don't bundle that grammar (the region is then left unhighlighted).
    private static func specKey(forInjection raw: String) -> String? {
        switch raw.lowercased() {
        case "javascript", "js", "jsx", "node": return "javascript"
        case "typescript", "ts", "tsx": return "typescript"
        case "json", "jsonc", "json5": return "json"
        case "html", "xml": return "html"
        case "css", "scss", "less": return "css"
        case "python", "py": return "python"
        case "bash", "sh", "shell", "zsh", "console": return "bash"
        case "swift": return "swift"
        case "sql": return "sql"
        case "php": return "php"
        case "yaml", "yml": return "yaml"
        case "markdown", "md": return "markdown"
        case "markdown_inline", "markdown.inline": return "markdown_inline"
        default: return nil
        }
    }

    // MARK: - Layer configurations

    /// Every grammar's compiled `LanguageConfiguration`, built once. Immutable
    /// and `Sendable`, so a single shared instance per grammar is reused across
    /// every parse — tree-sitter queries are read-only after compilation. Built
    /// lazily on first access; grammars whose queries fail to load are dropped.
    private static let configurations: [String: LanguageConfiguration] = {
        var map: [String: LanguageConfiguration] = [:]
        for (key, spec) in specs {
            guard let pointer = spec.language() else { continue }
            let language = Language(language: pointer)
            guard let highlights = query("highlights", spec.queryFolder, language) else { continue }
            var queries: [Query.Definition: Query] = [.highlights: highlights]
            // Injections are optional: a missing or malformed injections query
            // degrades to single-grammar highlighting rather than dropping the
            // language entirely.
            if let injections = query("injections", spec.queryFolder, language) {
                queries[.injections] = injections
            }
            map[key] = LanguageConfiguration(language, name: key, queries: queries)
        }
        return map
    }()

    /// The root layer configuration for an editor's selected language, or nil
    /// when the language has no grammar.
    static func configuration(for language: CodeLanguage) -> LanguageConfiguration? {
        specKey(for: language).flatMap { configurations[$0] }
    }

    /// The `LanguageLayer.LanguageProvider`: resolves an injected language name
    /// to its configuration, or nil to leave that nested region unhighlighted.
    static func injectedConfiguration(named name: String) -> LanguageConfiguration? {
        specKey(forInjection: name).flatMap { configurations[$0] }
    }

    private static func query(_ name: String, _ folder: String, _ language: Language) -> Query? {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "scm", subdirectory: "TreeSitter/\(folder)"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? Query(language: language, data: data)
    }

    // MARK: - Test support

    /// The tree-sitter parser language for `language`, or nil when it has none.
    static func language(for language: CodeLanguage) -> Language? {
        guard let key = specKey(for: language), let pointer = specs[key]?.language() else { return nil }
        return Language(language: pointer)
    }

    /// The compiled highlight query, throwing on a malformed query. Used by tests
    /// to verify every grammar is wired correctly; production code goes through
    /// `SyntaxHighlighter`, which degrades to no highlighting rather than throwing.
    static func compiledQuery(for language: CodeLanguage) throws -> Query? {
        guard
            let key = specKey(for: language),
            let spec = specs[key],
            let pointer = spec.language(),
            let url = Bundle.module.url(
                forResource: "highlights", withExtension: "scm",
                subdirectory: "TreeSitter/\(spec.queryFolder)")
        else { return nil }
        return try Query(language: Language(language: pointer), data: Data(contentsOf: url))
    }
}
