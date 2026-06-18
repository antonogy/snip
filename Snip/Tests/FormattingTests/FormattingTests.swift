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
}
