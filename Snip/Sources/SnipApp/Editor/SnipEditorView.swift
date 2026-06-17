import AppKit
import Highlighting
import SharedModels
import SwiftUI

/// SwiftUI wrapper around a TextKit 1 `NSTextView` with a line-number gutter,
/// word-wrap toggling, and current-line highlighting.
///
/// The gutter is a sibling view (`LineNumberGutterView`), not an `NSRulerView`:
/// a custom-drawing ruler breaks the text view's compositing inside SwiftUI's
/// host window. `EditorContainerView` lays the gutter and scroll view out
/// side by side and keeps the gutter redrawing as the text scrolls.
///
/// Syntax highlighting is applied as `.foregroundColor` attributes on the text
/// storage (never by replacing the string), so it leaves the undo stack, the
/// gutter's glyph geometry, and the current-line highlight untouched. Parsing
/// runs off the main actor on the `SyntaxHighlighter` actor and is debounced.
///
/// Undo/redo comes for free from `NSTextView`'s built-in undo manager.
struct SnipEditorView: NSViewRepresentable {
    @Binding var text: String
    var wordWrap: Bool
    var language: CodeLanguage

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
        context.coordinator.setLanguage(language, force: true)
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
            // Setting `.string` clears all attributes, so re-highlight afterwards.
            textView.string = text
            textView.typingAttributes = Self.defaultTypingAttributes
            context.coordinator.scheduleHighlight(immediate: true)
        }

        // A new detected/selected language rebuilds the grammar and re-highlights.
        context.coordinator.setLanguage(language)

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
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

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

        private let highlighter = SyntaxHighlighter()
        private let theme = HighlightTheme()
        private var currentLanguage: CodeLanguage = .plainText
        private var highlightTask: Task<Void, Never>?

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
                scheduleHighlight()
            }
        }

        // MARK: - Syntax highlighting

        /// Reconfigures the highlighter for `language` and re-highlights. A no-op
        /// when the language is unchanged unless `force` is set (used on first
        /// install, where `currentLanguage` still holds its default).
        func setLanguage(_ language: CodeLanguage, force: Bool = false) {
            guard force || language != currentLanguage else { return }
            currentLanguage = language
            highlightTask?.cancel()
            highlightTask = Task { [weak self, highlighter] in
                await highlighter.setLanguage(language)
                self?.scheduleHighlight(immediate: true)
            }
        }

        /// Parses the current text off the main actor and applies the resulting
        /// colors. Debounced by default so bursts of keystrokes coalesce; pass
        /// `immediate` to skip the delay (language change, content replacement).
        func scheduleHighlight(immediate: Bool = false) {
            highlightTask?.cancel()
            guard let text = textView?.string else { return }
            let expectedLength = (text as NSString).length
            highlightTask = Task { [weak self, highlighter] in
                if !immediate {
                    try? await Task.sleep(for: .milliseconds(40))
                    if Task.isCancelled { return }
                }
                let spans = await highlighter.highlights(for: text)
                if Task.isCancelled { return }
                self?.applySpans(spans, expectedLength: expectedLength)
            }
        }

        /// Applies foreground colors to the text storage. Attribute-only edits,
        /// wrapped in `begin/endEditing`, so the undo stack and the layout (and
        /// thus the gutter and current-line highlight) are untouched. Skips stale
        /// results whose source text length no longer matches the live document.
        private func applySpans(_ spans: [HighlightSpan], expectedLength: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let length = storage.length
            guard length == expectedLength else { return }

            storage.beginEditing()
            let full = NSRange(location: 0, length: length)
            storage.removeAttribute(.foregroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: theme.color(for: .plain), range: full)
            for span in spans where NSMaxRange(span.range) <= length && span.range.location >= 0 {
                storage.addAttribute(.foregroundColor, value: theme.color(for: span.token), range: span.range)
            }
            storage.endEditing()

            // An attribute-only edit doesn't reliably repaint a text view that
            // isn't the first responder (e.g. on launch before the editor gains
            // focus), so the colors would sit in storage unseen. Force the redraw
            // explicitly instead of relying on a focus change to trigger it.
            textView.needsDisplay = true
            gutter?.needsDisplay = true
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
