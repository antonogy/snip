import Foundation
import SharedModels
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterCSS
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterSql
import TreeSitterSwift
import TreeSitterTypeScript

/// Bridges Snip's `CodeLanguage` to the tree-sitter grammar and highlight query
/// for that language. Everything tree-sitter-specific is confined here so the
/// rest of the module (and `SharedModels`) never sees a grammar pointer.
enum Grammar {

    /// The tree-sitter parser language, or `nil` for `.plainText` (no grammar).
    static func language(for language: CodeLanguage) -> Language? {
        let pointer: OpaquePointer?
        switch language {
        case .javascript: pointer = tree_sitter_javascript()
        case .typescript: pointer = tree_sitter_typescript()
        case .json: pointer = tree_sitter_json()
        case .html: pointer = tree_sitter_html()
        case .css: pointer = tree_sitter_css()
        case .python: pointer = tree_sitter_python()
        case .bash: pointer = tree_sitter_bash()
        case .swift: pointer = tree_sitter_swift()
        case .sql: pointer = tree_sitter_sql()
        case .plainText: return nil
        }
        guard let pointer else { return nil }
        return Language(language: pointer)
    }

    /// Source of the bundled `highlights.scm` for a language, or `nil` when the
    /// language has no grammar or its query resource is missing.
    static func highlightQuerySource(for language: CodeLanguage) -> String? {
        guard let folder = queryFolder(for: language) else { return nil }
        guard
            let url = Bundle.module.url(
                forResource: "highlights",
                withExtension: "scm",
                subdirectory: "TreeSitter/\(folder)"
            )
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Builds the compiled highlight query for `language`, throwing if the
    /// grammar or query fails to load. Used by tests to verify every grammar is
    /// wired correctly; production code goes through `SyntaxHighlighter`, which
    /// degrades to no highlighting on failure rather than throwing.
    static func compiledQuery(for language: CodeLanguage) throws -> Query? {
        guard
            let tsLanguage = self.language(for: language),
            let source = highlightQuerySource(for: language)
        else { return nil }
        return try Query(language: tsLanguage, data: Data(source.utf8))
    }

    /// Folder name under `Resources/TreeSitter/` holding the query file.
    private static func queryFolder(for language: CodeLanguage) -> String? {
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
        case .plainText: return nil
        }
    }
}
