/// Product-wide safety limits (FR-21). Shared by the UI (to gate actions and
/// surface hints) and the storage layer (to enforce as a backstop).
public enum Limits {
    /// Maximum number of active snippets. "Active" excludes deleted and expired
    /// snippets held in Recovery. Creating beyond this is disabled, not blocked
    /// with a dialog (FR-21).
    public static let maxActiveSnippets = 100

    /// Provisional cap on the character count of a single editor's content. The
    /// concrete safe size is an open investigation (spec §10); until then this
    /// guards paste, drag-in, and large loads so the editor degrades gracefully
    /// rather than hanging (FR-21).
    public static let maxEditorCharacters = 1_000_000
}
