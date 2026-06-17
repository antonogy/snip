import Foundation

/// A colored run produced by the highlighter: a UTF-16 `NSRange` (so it maps
/// directly onto `NSTextStorage`) tagged with the token kind to color it.
///
/// A value type with only `Sendable` members, so it can safely cross the
/// `SyntaxHighlighter` actor boundary back to the main actor for display.
public struct HighlightSpan: Sendable, Equatable {
    public let range: NSRange
    public let token: HighlightToken

    public init(range: NSRange, token: HighlightToken) {
        self.range = range
        self.token = token
    }
}
