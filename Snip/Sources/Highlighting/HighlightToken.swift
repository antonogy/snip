/// A small, closed set of semantic token kinds the editor knows how to color.
///
/// Tree-sitter highlight queries use a large, open vocabulary of dotted capture
/// names (`@function.method`, `@keyword.return`, `@string.special.key`, …).
/// We collapse that vocabulary down to these few kinds so the color theme stays
/// tiny and grammar-agnostic. `.plain` means "leave it the default text color";
/// the engine emits no span for it.
public enum HighlightToken: String, Sendable, Equatable, CaseIterable {
    case keyword
    case string
    case comment
    case function
    case type
    case number
    case constant
    case property
    case plain

    /// Maps a tree-sitter capture name to a token by its first dotted component
    /// (so `@function.method` and `@function.builtin` both become `.function`).
    /// Anything we don't recognize falls back to `.plain`.
    public init(capture: String) {
        let root = capture.split(separator: ".").first.map(String.init) ?? capture
        switch root {
        case "keyword", "conditional", "repeat", "include", "import",
            "storageclass", "namespace", "label", "preproc",
            "media", "charset", "keyframes", "supports", "tag":
            self = .keyword
        case "string", "character", "char", "escape":
            self = .string
        case "comment":
            self = .comment
        case "function", "method", "constructor":
            self = .function
        case "type":
            self = .type
        case "number", "float":
            self = .number
        case "constant", "boolean":
            self = .constant
        case "property", "field", "attribute":
            self = .property
        default:
            self = .plain
        }
    }
}
