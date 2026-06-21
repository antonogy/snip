import Foundation
import SharedModels
import Testing

@testable import Highlighting

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {

    // MARK: - Grammar wiring

    /// GraphQL and Vue are format-only: no tree-sitter grammar ships for them via
    /// SwiftPM, so they intentionally do not highlight.
    static let formatOnly: Set<CodeLanguage> = [.graphql, .vue]

    @Test("Every highlightable language loads a grammar and compiles its query")
    func everyLanguageLoads() throws {
        for language in CodeLanguage.allCases
        where language != .plainText && !Self.formatOnly.contains(language) {
            let query = try Grammar.compiledQuery(for: language)
            #expect(query != nil, "\(language) failed to load a grammar/query")
        }
    }

    @Test("Languages without a grammar have none")
    func noGrammarLanguagesHaveNone() throws {
        for language in Self.formatOnly.union([.plainText]) {
            #expect(Grammar.language(for: language) == nil)
            #expect(try Grammar.compiledQuery(for: language) == nil)
        }
    }

    @Test("Flow reuses the JavaScript grammar")
    func flowReusesJavaScript() throws {
        #expect(Grammar.language(for: .flow) != nil)
        #expect(try Grammar.compiledQuery(for: .flow) != nil)
    }

    // MARK: - Highlighting behavior

    @Test("Plain text produces no spans")
    func plainTextProducesNoSpans() async {
        let spans = await highlight("just some prose here", as: .plainText)
        #expect(spans.isEmpty)
    }

    @Test("Empty text produces no spans")
    func emptyProducesNoSpans() async {
        let spans = await highlight("", as: .swift)
        #expect(spans.isEmpty)
    }

    @Test(
        "Each language highlights its keywords, comments, and strings",
        arguments: [
            Sample(
                language: .swift,
                source: "import Foundation\nfunc greet() {\n    let name = \"Snip\" // a label\n}",
                keyword: "func",
                comment: "// a label",
                string: "\"Snip\""
            ),
            Sample(
                language: .javascript,
                source: "// build a greeting\nfunction greet() {\n  const name = \"Snip\";\n}",
                keyword: "function",
                comment: "// build a greeting",
                string: "\"Snip\""
            ),
            Sample(
                language: .typescript,
                source: "// typed greeting\nfunction greet(name: string): void {\n  const x = \"hi\";\n}",
                keyword: "function",
                comment: "// typed greeting",
                string: "\"hi\""
            ),
            Sample(
                language: .python,
                source: "# greet the user\ndef greet(name):\n    msg = \"Snip\"\n    return msg",
                keyword: "def",
                comment: "# greet the user",
                string: "\"Snip\""
            ),
            Sample(
                language: .bash,
                source: "# a script\nif [ -n \"$name\" ]; then\n  echo \"hi\"\nfi",
                keyword: "if",
                comment: "# a script",
                string: "\"hi\""
            ),
            Sample(
                language: .css,
                source: "/* layout */\n.card {\n  color: #fff;\n}",
                keyword: nil,
                comment: "/* layout */",
                string: nil
            ),
            Sample(
                language: .sql,
                source: "-- find users\nSELECT name FROM users WHERE id = 1;",
                keyword: "SELECT",
                comment: "-- find users",
                string: nil
            ),
            Sample(
                language: .php,
                source: "<?php\n// greet\nfunction greet() {\n  $name = \"Snip\";\n}",
                keyword: "function",
                comment: "// greet",
                string: "\"Snip\""
            ),
            Sample(
                language: .yaml,
                source: "# config\nname: \"Snip\"\ncount: 42",
                keyword: nil,
                comment: "# config",
                string: "\"Snip\""
            ),
            Sample(
                language: .flow,
                source: "// typed greeting\nfunction greet(): void {\n  const x = \"hi\";\n}",
                keyword: "function",
                comment: "// typed greeting",
                string: "\"hi\""
            ),
        ]
    )
    func languageHighlights(sample: Sample) async {
        let spans = await highlight(sample.source, as: sample.language)
        #expect(!spans.isEmpty, "\(sample.language) produced no spans")

        if let keyword = sample.keyword {
            #expect(
                token(at: offset(keyword, sample.source), in: spans) == .keyword,
                "\(sample.language): expected '\(keyword)' to be a keyword"
            )
        }
        if let comment = sample.comment {
            #expect(
                token(at: offset(comment, sample.source), in: spans) == .comment,
                "\(sample.language): expected '\(comment)' to be a comment"
            )
        }
        if let string = sample.string {
            #expect(
                token(at: offset(string, sample.source), in: spans) == .string,
                "\(sample.language): expected '\(string)' to be a string"
            )
        }
    }

    @Test("JSON highlights strings and numbers")
    func jsonHighlights() async {
        let source = #"{ "name": "Snip", "count": 42 }"#
        let spans = await highlight(source, as: .json)
        #expect(token(at: offset("\"Snip\"", source), in: spans) == .string)
        #expect(token(at: offset("42", source), in: spans) == .number)
    }

    @Test("HTML highlights tags and comments")
    func htmlHighlights() async {
        let source = "<!-- page -->\n<div class=\"card\"></div>"
        let spans = await highlight(source, as: .html)
        #expect(!spans.isEmpty)
        #expect(token(at: offset("<!-- page -->", source), in: spans) == .comment)
    }

    @Test("Markdown highlights its structure")
    func markdownHighlights() async {
        let source = "# Title\n\nSome **bold** text and a [link](https://x).\n"
        let spans = await highlight(source, as: .markdown)
        #expect(!spans.isEmpty, "markdown produced no spans")
    }

    @Test("Angular template highlights")
    func angularHighlights() async {
        let source = "<div>{{ title }}</div>\n<button (click)=\"save()\">Go</button>"
        let spans = await highlight(source, as: .angular)
        #expect(!spans.isEmpty, "angular produced no spans")
    }

    @Test("GraphQL and Vue do not highlight (format-only)")
    func formatOnlyLanguagesProduceNoSpans() async {
        let gql = await highlight("type Query { user: User }", as: .graphql)
        #expect(gql.isEmpty)
        let vue = await highlight("<template><p>{{ x }}</p></template>", as: .vue)
        #expect(vue.isEmpty)
    }

    @Test("Markdown injects highlighting into fenced code blocks")
    func markdownInjectsFencedCode() async {
        // The Swift `let`/`func` keywords live only inside the fenced block; if
        // they are highlighted, the JavaScriptCore-free injection path is working.
        let source = """
            # Example

            ```swift
            let answer = 42
            ```
            """
        let spans = await highlight(source, as: .markdown)
        #expect(
            token(at: offset("let", source), in: spans) == .keyword,
            "expected the injected Swift `let` inside the fence to highlight"
        )
    }

    @Test("HTML injects highlighting into embedded style and script")
    func htmlInjectsEmbeddedLanguages() async {
        let source = "<style>.a { color: #fff; }</style><script>const x = 1;</script>"
        let spans = await highlight(source, as: .html)
        // `const` is a JS keyword that only appears inside the <script> block.
        #expect(
            token(at: offset("const", source), in: spans) == .keyword,
            "expected injected JavaScript inside <script> to highlight"
        )
    }

    @Test(
        "Highlighting every prefix of a snippet never crashes",
        arguments: CodeLanguage.allCases
    )
    func partialInputDoesNotCrash(language: CodeLanguage) async {
        // Mimics typing: each growing prefix is partial, often syntactically
        // invalid input. A grammar's external scanner must tolerate this rather
        // than `abort()` on it (the python scanner's `assert(false)` did).
        let source = """
            # comment
            def greet(name):
                msg = "Snip's \\"value\\""
                items = [1, 2, 3]
                return f'{msg} {name}'
            <div class="x">SELECT * FROM t; .a{color:#fff}</div>
            const x = `tmpl ${y}`; echo "hi $USER"
            """
        let highlighter = SyntaxHighlighter()
        await highlighter.setLanguage(language)
        let scalars = Array(source.unicodeScalars)
        for end in stride(from: 0, through: scalars.count, by: 1) {
            let prefix = String(String.UnicodeScalarView(scalars[0..<end]))
            _ = await highlighter.highlights(for: prefix)
        }
    }

    // MARK: - Helpers

    struct Sample: Sendable {
        let language: CodeLanguage
        let source: String
        let keyword: String?
        let comment: String?
        let string: String?
    }

    private func highlight(_ source: String, as language: CodeLanguage) async -> [HighlightSpan] {
        let highlighter = SyntaxHighlighter()
        await highlighter.setLanguage(language)
        return await highlighter.highlights(for: source)
    }

    /// UTF-16 offset of the first occurrence of `needle` in `haystack`.
    private func offset(_ needle: String, _ haystack: String) -> Int {
        guard let range = haystack.range(of: needle) else { return -1 }
        return haystack.utf16.distance(
            from: haystack.utf16.startIndex, to: range.lowerBound.samePosition(in: haystack.utf16)!)
    }

    /// The token the editor actually shows at `index`: spans are ordered
    /// widest-first and applied last-wins, so the visible color is the last
    /// (narrowest, deepest) span covering the index.
    private func token(at index: Int, in spans: [HighlightSpan]) -> HighlightToken? {
        spans.last { NSLocationInRange(index, $0.range) }?.token
    }
}
