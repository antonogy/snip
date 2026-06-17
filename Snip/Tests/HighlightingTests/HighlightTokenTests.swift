import Testing

@testable import Highlighting

@Suite("HighlightToken capture mapping")
struct HighlightTokenTests {

    @Test("Dotted capture names map by their first component")
    func dottedNamesMapByRoot() {
        #expect(HighlightToken(capture: "function") == .function)
        #expect(HighlightToken(capture: "function.method") == .function)
        #expect(HighlightToken(capture: "function.builtin") == .function)
        #expect(HighlightToken(capture: "keyword.return") == .keyword)
        #expect(HighlightToken(capture: "string.special.key") == .string)
        #expect(HighlightToken(capture: "number.float") == .number)
        #expect(HighlightToken(capture: "constant.builtin") == .constant)
        #expect(HighlightToken(capture: "type.builtin") == .type)
        #expect(HighlightToken(capture: "comment.documentation") == .comment)
    }

    @Test("Unrecognized captures fall back to plain")
    func unknownIsPlain() {
        #expect(HighlightToken(capture: "variable") == .plain)
        #expect(HighlightToken(capture: "operator") == .plain)
        #expect(HighlightToken(capture: "punctuation.bracket") == .plain)
        #expect(HighlightToken(capture: "something.unheard.of") == .plain)
    }
}
