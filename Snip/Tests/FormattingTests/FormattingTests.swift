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

    @Test("Plain Text has no formatter")
    func plainTextUnsupported() async throws {
        await #expect(throws: FormatterError.unsupportedLanguage(.plainText)) {
            try await formatter.format("anything", language: .plainText)
        }
    }

    @Test("Blank input is returned unchanged without spawning a tool")
    func blankInputNoOp() throws {
        let spec = ProcessFormatter.CommandSpec(executable: "definitely-not-installed", arguments: [])
        let result = try ProcessFormatter.run(spec: spec, input: "   \n\t", language: .bash)
        #expect(result == "   \n\t")
    }

    @Test("Missing CLI tool surfaces toolNotFound")
    func missingToolErrors() throws {
        let spec = ProcessFormatter.CommandSpec(executable: "snip-no-such-formatter", arguments: [])
        #expect(throws: FormatterError.toolNotFound(tool: "snip-no-such-formatter", language: .bash)) {
            try ProcessFormatter.run(spec: spec, input: "echo hi", language: .bash)
        }
    }
}

/// Exercises the process runner's PATH resolution, stdin→stdout piping, and
/// exit-code mapping using tools present on every macOS, so the machinery is
/// covered even when no real formatter CLI is installed.
@Suite("Process runner machinery")
struct ProcessRunnerTests {
    @Test("Pipes input through a stdin→stdout tool and returns its output")
    func pipesThroughTool() throws {
        // `sed` reads stdin, applies the substitution, writes stdout.
        let spec = ProcessFormatter.CommandSpec(executable: "sed", arguments: ["s/foo/bar/g"])
        let result = try ProcessFormatter.run(spec: spec, input: "foo foo\n", language: .bash)
        #expect(result == "bar bar\n")
    }

    @Test("Non-zero exit maps to executionFailed with stderr")
    func nonZeroExitErrors() throws {
        // `sh -c 'echo boom >&2; exit 1'` exits non-zero and writes to stderr.
        let spec = ProcessFormatter.CommandSpec(
            executable: "sh", arguments: ["-c", "echo boom >&2; exit 1"])
        #expect {
            try ProcessFormatter.run(spec: spec, input: "ignored", language: .bash)
        } throws: { error in
            guard case .executionFailed(let tool, let message) = error as? FormatterError else {
                return false
            }
            return tool == "sh" && message.contains("boom")
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

@Suite("CLI command registry")
struct CommandRegistryTests {
    @Test(
        "Each CLI language maps to the expected tool invocation",
        arguments: [
            (CodeLanguage.sql, "sql-formatter", []),
            (.python, "black", ["-q", "-"]),
            (.bash, "shfmt", []),
        ]
    )
    func mapsLanguageToCommand(language: CodeLanguage, executable: String, arguments: [String]) {
        let spec = ProcessFormatter.commandSpec(for: language)
        #expect(spec?.executable == executable)
        #expect(spec?.arguments == arguments)
    }

    @Test(
        "In-process and unsupported languages have no CLI command",
        arguments: [
            CodeLanguage.swift, .plainText, .javascript, .typescript, .json, .html, .css,
        ]
    )
    func noCommandForInProcessLanguages(language: CodeLanguage) {
        #expect(ProcessFormatter.commandSpec(for: language) == nil)
    }

    @Test("Augmented PATH includes Homebrew and stays free of duplicates")
    func augmentedPathIncludesHomebrew() {
        let path = ProcessFormatter.augmentedPath()
        let dirs = path.split(separator: ":").map(String.init)
        #expect(dirs.contains("/opt/homebrew/bin"))
        #expect(Set(dirs).count == dirs.count)
    }
}
