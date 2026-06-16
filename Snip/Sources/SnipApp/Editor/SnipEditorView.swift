import AppKit
import SwiftUI

/// SwiftUI wrapper around a TextKit 1 `NSTextView` with a line-number gutter,
/// word-wrap toggling, and current-line highlighting.
///
/// The gutter is a sibling view (`LineNumberGutterView`), not an `NSRulerView`:
/// a custom-drawing ruler breaks the text view's compositing inside SwiftUI's
/// host window. `EditorContainerView` lays the gutter and scroll view out
/// side by side and keeps the gutter redrawing as the text scrolls.
///
/// Undo/redo comes for free from `NSTextView`'s built-in undo manager.
struct SnipEditorView: NSViewRepresentable {
    @Binding var text: String
    var wordWrap: Bool

    private static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.textColor,
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditorContainerView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        // Frame-only init constructs the modern (TextKit 2) stack; touching
        // `.layoutManager` downgrades the view to TextKit 1, which the
        // line-number gutter needs for its glyph-based geometry queries.
        let textView = HighlightingTextView(frame: .zero)
        let layoutManager = textView.layoutManager
        layoutManager?.backgroundLayoutEnabled = false
        textView.textContainer?.widthTracksTextView = true
        configure(textView: textView, scrollView: scrollView)
        textView.string = text
        // Setting .string resets typingAttributes; re-pin them so newly typed
        // characters inherit the correct font and color.
        textView.typingAttributes = Self.defaultTypingAttributes
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView

        let gutter = LineNumberGutterView(textView: textView, scrollView: scrollView)
        context.coordinator.gutter = gutter

        applyWordWrap(wordWrap, to: textView, scrollView: scrollView)
        return EditorContainerView(scrollView: scrollView, gutter: gutter)
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        let scrollView = container.scrollView
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self

        // The textView starts with a zero frame from makeNSView (the scroll view
        // has no real size yet at that point). autoresizingMask can't resize from
        // zero, so we set the frame explicitly here where contentSize is guaranteed
        // to be non-zero after SwiftUI's first layout pass.
        let cw = scrollView.contentSize.width
        let ch = scrollView.contentSize.height
        if cw > 0 && textView.frame.width < 1 {
            textView.frame = NSRect(x: 0, y: 0, width: cw, height: ch)
            textView.minSize = NSSize(width: 0, height: ch)
        }

        if textView.string != text {
            // Preserve the undo stack: only replace content when it truly drifted.
            textView.string = text
            textView.typingAttributes = Self.defaultTypingAttributes
        }

        applyWordWrap(wordWrap, to: textView, scrollView: scrollView)
        container.gutter.needsDisplay = true
    }

    // MARK: - Private helpers

    private func configure(textView: HighlightingTextView, scrollView: NSScrollView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.drawsBackground = true

        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor

        textView.textContainerInset = NSSize(width: 4, height: 8)

        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Disable spell-check and autocorrection — this is a code editor.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
    }

    private func applyWordWrap(
        _ enabled: Bool,
        to textView: NSTextView,
        scrollView: NSScrollView
    ) {
        if enabled {
            textView.textContainer?.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
        } else {
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SnipEditorView
        weak var textView: NSTextView?
        weak var gutter: LineNumberGutterView?

        init(_ parent: SnipEditorView) {
            self.parent = parent
        }

        // `notification` is not Sendable in Swift 6, so we ignore it and
        // read from the already-@MainActor-isolated `textView` reference instead.
        nonisolated func textDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                let newText = textView?.string ?? ""
                if parent.text != newText {
                    parent.text = newText
                }
                gutter?.needsDisplay = true
            }
        }
    }
}

/// Hosts the editor's scroll view with the line-number gutter pinned to its
/// left edge, and keeps the gutter repainting as the text scrolls.
final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    let gutter: LineNumberGutterView

    init(scrollView: NSScrollView, gutter: LineNumberGutterView) {
        self.scrollView = scrollView
        self.gutter = gutter
        super.init(frame: .zero)
        addSubview(gutter)
        addSubview(scrollView)

        // Repaint line numbers whenever the document scrolls.
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: clip
        )
    }

    required init?(coder: NSCoder) { fatalError("use init(scrollView:gutter:)") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func documentDidScroll() {
        gutter.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let w = LineNumberGutterView.width
        gutter.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
        scrollView.frame = NSRect(x: w, y: 0, width: max(0, bounds.width - w), height: bounds.height)
    }
}
