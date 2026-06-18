import AppKit

/// NSTextView subclass that draws a subtle highlight behind the line containing
/// the insertion point. The highlight is suppressed whenever there is a
/// non-empty selection, because the standard selection highlight is already
/// present.
final class HighlightingTextView: NSTextView {

    /// Fired when this view becomes first responder, so the app can track which
    /// editor (main vs split) is focused for content-targeted commands like Format.
    var onBecomeFirstResponder: (() -> Void)?

    /// Whether this view claims first responder as soon as it's installed in a
    /// window. Only the main editor does; the split editor must not steal focus
    /// when it appears (opening a split snippet keeps the cursor in the main editor).
    var claimsFocusOnInstall = true

    /// Replaces the entire document through the standard editing path so the
    /// change is registered with the undo manager (⌘Z reverts it in one step)
    /// and `textDidChange` fires — driving the binding update, autosave, and
    /// re-highlight. Used by Format Code.
    func replaceAllText(_ newText: String) {
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard newText != string, shouldChangeText(in: full, replacementString: newText) else { return }
        textStorage?.replaceCharacters(in: full, with: newText)
        didChangeText()
    }

    /// Reveals this text view's own find bar (FR-19). The find bar belongs to the
    /// enclosing scroll view, so the search is scoped to this editor alone — it
    /// never reaches the other editor in a split or any other snippet.
    func showFindInterface() {
        let item = NSMenuItem()
        item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        performTextFinderAction(item)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onBecomeFirstResponder?() }
        return became
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard selectedRange().length == 0,
            let lm = layoutManager,
            let tc = textContainer
        else { return }

        lm.ensureLayout(for: tc)

        let lineRect: NSRect
        if lm.numberOfGlyphs == 0 {
            // Empty document: the only "line" is the extra line fragment.
            lineRect = lm.extraLineFragmentRect
        } else {
            let charIndex = min(selectedRange().location, (string as NSString).length)
            let glyphIndex = min(lm.glyphIndexForCharacter(at: charIndex), lm.numberOfGlyphs - 1)
            let fragmentRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            // Cursor after a trailing newline lands in the extra fragment.
            lineRect = fragmentRect.isEmpty ? lm.extraLineFragmentRect : fragmentRect
        }

        guard !lineRect.isEmpty else { return }

        var highlight = lineRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        highlight.origin.x = 0
        highlight.size.width = bounds.width

        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: highlight).fill()
    }

    // Claim first responder as soon as the view is installed in a window so
    // the user can start typing without clicking first. The split editor opts
    // out (`claimsFocusOnInstall == false`) so it never steals focus from the
    // main editor when a split snippet is opened.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, claimsFocusOnInstall {
            window?.makeFirstResponder(self)
        }
    }

    // Invalidate drawing whenever the cursor or selection changes so the
    // highlight follows the insertion point immediately.
    override func setSelectedRange(
        _ charRange: NSRange,
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        needsDisplay = true
    }
}
