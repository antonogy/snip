import Foundation
import Prettier
import PrettierBabel
import PrettierGraphQL
import PrettierHTML
import PrettierMarkdown
import PrettierPHP
import PrettierPostCSS
import PrettierTypeScript
import PrettierYAML
import SharedModels

/// In-process formatting for the Prettier-backed languages (JavaScript,
/// TypeScript, JSON, CSS, HTML) using the bundled `simonbs/Prettier` package,
/// which runs Prettier itself in JavaScriptCore. No external `npm`/CLI install
/// is required, so these languages format with zero setup and deterministically.
///
/// `PrettierFormatter` wraps a `JSContext` and is not `Sendable`; an instance is
/// created, prepared, and used entirely within a single synchronous `format`
/// call and never crosses a task or actor boundary.
enum PrettierFormatting {
    /// Languages handled here rather than by an external CLI.
    static func handles(_ language: CodeLanguage) -> Bool {
        configuration(for: language) != nil
    }

    /// Formats `text` for `language`, or throws a ``FormatterError``. Blank input
    /// formats to itself. The caller guarantees `language` is Prettier-backed.
    static func format(_ text: String, language: CodeLanguage) throws -> String {
        guard let config = configuration(for: language) else {
            throw FormatterError.unsupportedLanguage(language)
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        let formatter = PrettierFormatter(plugins: config.plugins, parser: config.parser)
        formatter.prepare()
        switch formatter.format(text) {
        case .success(let output):
            return output
        case .failure(let error):
            throw FormatterError.executionFailed(
                tool: "prettier", message: error.errorDescription ?? "\(error)")
        }
    }

    /// The plugins + parser Prettier needs for a language, or `nil` when the
    /// language is handled elsewhere (Swift in-process, others via CLI).
    private static func configuration(
        for language: CodeLanguage
    ) -> (plugins: [Plugin], parser: Parser)? {
        switch language {
        case .javascript:
            return ([BabelPlugin()], BabelParser())
        case .typescript:
            return ([TypeScriptPlugin()], TypeScriptParser())
        case .json:
            // The JSON parser ships inside the Babel plugin.
            return ([BabelPlugin()], JSONParser())
        case .css:
            return ([PostCSSPlugin()], CSSParser())
        case .html:
            // HTML embeds CSS and JS, so it needs the PostCSS and Babel plugins too.
            return ([HTMLPlugin(), PostCSSPlugin(), BabelPlugin()], HTMLParser())
        case .markdown:
            return ([MarkdownPlugin()], MarkdownParser())
        case .yaml:
            return ([YAMLPlugin()], YAMLParser())
        case .php:
            return ([PHPPlugin()], PHPParser())
        case .graphql:
            return ([GraphQLPlugin()], GraphQLParser())
        case .flow:
            // Flow is parsed by Babel's Flow-aware parser, which lives in the
            // Babel plugin (the standalone Flow plugin exposes a different parser
            // name that this build of Prettier does not return a string for).
            return ([BabelPlugin()], BabelFlowParser())
        case .vue:
            // Vue single-file components embed CSS and JS like HTML.
            return ([HTMLPlugin(), PostCSSPlugin(), BabelPlugin()], VueParser())
        case .angular:
            // Angular templates embed CSS and JS like HTML.
            return ([HTMLPlugin(), PostCSSPlugin(), BabelPlugin()], AngularParser())
        case .sql, .python, .bash, .swift, .plainText:
            return nil
        }
    }
}
