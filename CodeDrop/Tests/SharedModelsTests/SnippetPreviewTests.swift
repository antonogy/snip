import Testing

@testable import SharedModels

@Suite("SnippetPreview")
struct SnippetPreviewTests {

    @Test("Empty content yields no preview lines")
    func emptyIsEmpty() {
        #expect(SnippetPreview.previewLines(from: "") == [])
        #expect(SnippetPreview.previewLines(from: "   \n\t\n  ") == [])
    }

    @Test("Blank and whitespace-only lines are skipped")
    func skipsBlankLines() {
        let text = "\n\n  func a() {\n\n   let b = 1\n"
        #expect(SnippetPreview.previewLines(from: text) == ["func a() {", "let b = 1"])
    }

    @Test("Returns at most the first maxLines non-empty lines")
    func capsAtMaxLines() {
        let text = "one\ntwo\nthree\nfour\nfive"
        #expect(SnippetPreview.previewLines(from: text) == ["one", "two", "three"])
        #expect(SnippetPreview.previewLines(from: text, maxLines: 2) == ["one", "two"])
    }

    @Test("Handles CRLF line endings")
    func handlesCRLF() {
        let text = "alpha\r\nbeta\r\ngamma"
        #expect(SnippetPreview.previewLines(from: text) == ["alpha", "beta", "gamma"])
    }

    @Test("previewTitle is the first non-empty line")
    func titleIsFirstLine() {
        #expect(SnippetPreview.previewTitle(from: "\n\n  hello world \n more") == "hello world")
        #expect(SnippetPreview.previewTitle(from: "") == "")
    }
}
