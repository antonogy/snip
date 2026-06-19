import Foundation
import SharedModels
import Testing

@testable import Highlighting

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {

    // MARK: - Grammar wiring

    @Test("Every supported language loads a grammar and compiles its query")
    func everyLanguageLoads() throws {
        for language in CodeLanguage.allCases where language != .plainText {
            let query = try Grammar.compiledQuery(for: language)
            #expect(query != nil, "\(language) failed to load a grammar/query")
        }
    }

    @Test("Plain text has no grammar")
    func plainTextHasNoGrammar() throws {
        #expect(Grammar.language(for: .plainText) == nil)
        #expect(try Grammar.compiledQuery(for: .plainText) == nil)
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

    private func token(at index: Int, in spans: [HighlightSpan]) -> HighlightToken? {
        spans.first { NSLocationInRange(index, $0.range) }?.token
    }
}
