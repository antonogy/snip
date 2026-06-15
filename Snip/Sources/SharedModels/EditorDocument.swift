import Foundation

/// A single editable buffer. Its text lives in a separate content file
/// (`contentFilePath`); this struct holds only the metadata.
public struct EditorDocument: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID

    /// Path, relative to the container's `contents/` directory, of the backing text file.
    public var contentFilePath: String

    public var language: CodeLanguage
    public var languageMode: LanguageMode

    public var cursorPosition: Int?
    public var selectedRange: TextRange?
    public var scrollOffset: Double?

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        contentFilePath: String,
        language: CodeLanguage = .plainText,
        languageMode: LanguageMode = .auto,
        cursorPosition: Int? = nil,
        selectedRange: TextRange? = nil,
        scrollOffset: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.contentFilePath = contentFilePath
        self.language = language
        self.languageMode = languageMode
        self.cursorPosition = cursorPosition
        self.selectedRange = selectedRange
        self.scrollOffset = scrollOffset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
