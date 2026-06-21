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
        let components = capture.split(separator: ".").map(String.init)
        let root = components.first ?? capture
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
        // Prose markup (Markdown headings, emphasis, code, links). These grammars
        // use `text.*` / `markup.*` capture names with no analogue in code, so the
        // sub-kind picks a reasonable color: headings/emphasis read as keywords,
        // inline code as strings, link URLs as constants, link text as properties.
        case "text", "markup":
            switch components.count > 1 ? components[1] : "" {
            case "literal", "raw", "code":
                self = .string
            case "uri", "link", "url":
                self = .constant
            case "reference":
                self = .property
            default:
                self = .keyword
            }
        default:
            self = .plain
        }
    }
}
