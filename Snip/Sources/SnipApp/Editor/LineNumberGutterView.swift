import AppKit

/// Line-number gutter drawn as a plain sibling view beside the editor's scroll
/// view — deliberately **not** an `NSRulerView`.
///
/// A custom-drawing `NSRulerView` set as a scroll view's `verticalRulerView`
/// breaks layer compositing of the document (text) view when the scroll view is
/// hosted inside SwiftUI, leaving the editor blank. An ordinary `NSView` next to
/// the scroll view composites correctly and gives us full control over the
/// numbers.
///
/// Operates exclusively in TextKit 1 mode — `SnipEditorView` must build the text
/// stack with `NSLayoutManager` before attaching this gutter.
final class LineNumberGutterView: NSView {

    static let width: CGFloat = 44

    private static let gutterFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let gutterColor = NSColor.tertiaryLabelColor
    private static let gutterBackground = NSColor.windowBackgroundColor

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("use init(textView:scrollView:)") }

    // Draw top-down so y math matches the text view's flipped coordinate space.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Self.gutterBackground.set()
        dirtyRect.fill()

        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let string = textView.string as NSString
        let textLength = string.length
        let scrollOffset = scrollView?.contentView.bounds.origin.y ?? 0
        let containerOriginY = textView.textContainerOrigin.y

        var lineNumber = 1
        var charIndex = 0

        // Iterate logical lines (paragraphs). Each paragraph gets one line number
        // regardless of how many visual rows word-wrap produces.
        while charIndex < textLength {
            let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let y = lineRect.minY + containerOriginY - scrollOffset

            drawNumber(lineNumber, y: y, height: lineRect.height, in: dirtyRect)

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }

        // Extra line fragment: text ends with a newline, or the buffer is empty.
        let extraRect = layoutManager.extraLineFragmentRect
        if !extraRect.isEmpty {
            let y = extraRect.minY + containerOriginY - scrollOffset
            drawNumber(lineNumber, y: y, height: extraRect.height, in: dirtyRect)
        }

        // Right-edge hairline separator.
        NSColor.separatorColor.set()
        NSBezierPath(
            rect: NSRect(x: bounds.maxX - 0.5, y: dirtyRect.minY, width: 0.5, height: dirtyRect.height)
        ).fill()
    }

    private func drawNumber(_ number: Int, y: CGFloat, height: CGFloat, in dirtyRect: NSRect) {
        guard y < dirtyRect.maxY && (y + height) > dirtyRect.minY else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.gutterFont,
            .foregroundColor: Self.gutterColor,
        ]
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attrs)
        let drawPoint = NSPoint(
            x: bounds.maxX - size.width - 10,
            y: y + (height - size.height) / 2
        )
        label.draw(at: drawPoint, withAttributes: attrs)
    }
}
