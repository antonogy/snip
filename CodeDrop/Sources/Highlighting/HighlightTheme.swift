import AppKit

/// Maps `HighlightToken`s to editor colors. Each color is a *dynamic* `NSColor`
/// that resolves to a light or dark variant against the view's appearance, so
/// flipping the app between light and dark recolors the text without the editor
/// having to re-highlight.
///
/// The palette is deliberately restrained — a calm, Xcode-Default-spirit set
/// rather than a saturated IDE theme. `.plain` is the system text color, so
/// ordinary identifiers, operators, and punctuation stay unstyled.
public struct HighlightTheme {

    public init() {}

    public func color(for token: HighlightToken) -> NSColor {
        switch token {
        case .plain: return .textColor
        case .comment: return .secondaryLabelColor
        case .keyword: return keyword
        case .string: return string
        case .function: return function
        case .type: return type
        case .number: return number
        case .constant: return constant
        case .property: return property
        }
    }

    private let keyword = dynamic(light: 0x9B2393, dark: 0xFF7AB2)
    private let string = dynamic(light: 0xC41A16, dark: 0xFF8170)
    private let function = dynamic(light: 0x0058A1, dark: 0x6FB7FF)
    private let type = dynamic(light: 0x0F7D8C, dark: 0x5DD8FF)
    private let number = dynamic(light: 0x1C00CF, dark: 0xD0BF69)
    private let constant = dynamic(light: 0x6F42C1, dark: 0xB281EB)
    private let property = dynamic(light: 0x2A6FB0, dark: 0x79C0FF)

    /// Builds an appearance-aware color from two packed `0xRRGGBB` values.
    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        let lightColor = NSColor(rgb: light)
        let darkColor = NSColor(rgb: dark)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? darkColor : lightColor
        }
    }
}

extension NSColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
