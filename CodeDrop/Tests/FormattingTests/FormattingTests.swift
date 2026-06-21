import Foundation
import SharedModels
import Testing

@testable import Formatting

@Suite("Swift formatting (bundled, deterministic)")
struct SwiftFormattingTests {
    let formatter = CodeFormatter()

    @Test("Reindents and normalizes messy Swift source")
    func reindentsSwift() async throws {
        let messy = "struct  Foo{let x=1\nfunc bar()->Int{return x}}"
        let formatted = try await formatter.format(messy, language: .swift)

        #expect(formatted != messy)
        // swift-format normalizes the spacing around operators and braces.
        #expect(formatted.contains("let x = 1"))
        #expect(formatted.contains("-> Int"))
    }

    @Test("Formatting is idempotent")
    func idempotent() async throws {
        let messy = "enum E{case a\ncase b}"
        let once = try await formatter.format(messy, language: .swift)
        let twice = try await formatter.format(once, language: .swift)
        #expect(once == twice)
    }

    @Test("Already-formatted source is preserved")
    func preservesCleanSource() async throws {
        let clean = "let answer = 42\n"
        let formatted = try await formatter.format(clean, language: .swift)
        #expect(formatted == clean)
    }
}

@Suite("Formatter routing and errors")
struct FormatterRoutingTests {
    let formatter = CodeFormatter()

    @Test(
        "Languages with a built-in formatter are supported",
        arguments: [
            CodeLanguage.swift, .javascript, .typescript, .json, .css, .html,
            .markdown, .yaml, .php, .graphql, .flow, .vue, .angular,
        ]
    )
    func supportedLanguages(language: CodeLanguage) {
        #expect(formatter.supports(language))
    }

    @Test(
        "Languages without a built-in formatter are unsupported",
        arguments: [
            CodeLanguage.sql, .python, .bash, .plainText,
        ]
    )
    func unsupportedLanguages(language: CodeLanguage) async throws {
        #expect(!formatter.supports(language))
        await #expect(throws: FormatterError.unsupportedLanguage(language)) {
            try await formatter.format("anything", language: language)
        }
    }
}

@Suite("Prettier formatting (bundled JavaScriptCore, deterministic)")
struct PrettierFormattingTests {
    let formatter = CodeFormatter()

    @Test("Pretty-prints minified JSON")
    func formatsJSON() async throws {
        let messy = "{\"b\":2,\"a\":[1,2,3]}"
        let formatted = try await formatter.format(messy, language: .json)
        #expect(formatted != messy)
        #expect(formatted.contains("\"b\": 2"))
        #expect(formatted.contains("\n"))
    }

    @Test("Normalizes JavaScript spacing and quotes")
    func formatsJavaScript() async throws {
        let messy = "const   foo=1\nfunction bar( ){return foo}"
        let formatted = try await formatter.format(messy, language: .javascript)
        #expect(formatted.contains("const foo = 1"))
    }

    @Test("Formats TypeScript with type annotations")
    func formatsTypeScript() async throws {
        let messy = "let   x:number=1;function f(a:string){return a}"
        let formatted = try await formatter.format(messy, language: .typescript)
        #expect(formatted.contains("let x: number = 1"))
    }

    @Test("Formats CSS declarations")
    func formatsCSS() async throws {
        let messy = "a{color:red;font-weight:bold}"
        let formatted = try await formatter.format(messy, language: .css)
        #expect(formatted.contains("color: red"))
        #expect(formatted.contains("\n"))
    }

    @Test("Formats HTML structure")
    func formatsHTML() async throws {
        let messy = "<div><span>hi</span></div>"
        let formatted = try await formatter.format(messy, language: .html)
        #expect(formatted.contains("<span>hi</span>"))
    }

    @Test(
        "Prettier formatting is idempotent",
        arguments: [
            (CodeLanguage.json, "{\"a\":1}"),
            (.javascript, "const  x=1"),
            (.css, "a{color:red}"),
        ]
    )
    func idempotent(language: CodeLanguage, messy: String) async throws {
        let once = try await formatter.format(messy, language: language)
        let twice = try await formatter.format(once, language: language)
        #expect(once == twice)
    }

    @Test("Formats Markdown")
    func formatsMarkdown() async throws {
        let messy = "#  Title\n\n\n*  one\n*  two\n"
        let formatted = try await formatter.format(messy, language: .markdown)
        #expect(formatted.contains("# Title"))
        #expect(formatted != messy)
    }

    @Test("Formats YAML")
    func formatsYAML() async throws {
        let messy = "a:     1\nb:   2\n"
        let formatted = try await formatter.format(messy, language: .yaml)
        #expect(formatted.contains("a: 1"))
        #expect(formatted.contains("b: 2"))
    }

    @Test("Formats PHP")
    func formatsPHP() async throws {
        let messy = "<?php\nfunction   f(){return 1;}"
        let formatted = try await formatter.format(messy, language: .php)
        #expect(formatted != messy)
        #expect(formatted.contains("function f()"))
    }

    @Test("Formats GraphQL")
    func formatsGraphQL() async throws {
        let messy = "query{user{id   name}}"
        let formatted = try await formatter.format(messy, language: .graphql)
        #expect(formatted.contains("query {"))
        #expect(formatted.contains("\n"))
    }

    @Test("Formats Flow")
    func formatsFlow() async throws {
        let messy = "const   x=1\nfunction f(a: number){return a}"
        let formatted = try await formatter.format(messy, language: .flow)
        #expect(formatted.contains("const x = 1"))
    }

    @Test("Formats Vue single-file components")
    func formatsVue() async throws {
        let messy = "<template><p>{{x}}</p></template>"
        let formatted = try await formatter.format(messy, language: .vue)
        #expect(formatted.contains("<template>"))
        #expect(formatted != messy)
    }

    @Test("Formats Angular templates")
    func formatsAngular() async throws {
        let messy = "<div>\n<p>{{ x }}</p>\n  <span>hi</span></div>"
        let formatted = try await formatter.format(messy, language: .angular)
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("<span>hi</span>"))
        // Idempotent: re-formatting the result is a no-op.
        let twice = try await formatter.format(formatted, language: .angular)
        #expect(twice == formatted)
    }

    @Test(
        "Prettier formatting of the added languages is idempotent",
        arguments: [
            (CodeLanguage.markdown, "# Title\n\nText.\n"),
            (.yaml, "a: 1\nb: 2\n"),
            (.php, "<?php\nfunction f()\n{\n    return 1;\n}\n"),
            (.graphql, "query {\n  user {\n    id\n  }\n}\n"),
            (.flow, "const x = 1;\n"),
        ]
    )
    func idempotentAddedLanguages(language: CodeLanguage, clean: String) async throws {
        let once = try await formatter.format(clean, language: language)
        let twice = try await formatter.format(once, language: language)
        #expect(once == twice)
    }
}
