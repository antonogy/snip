import Foundation

/// A scratchpad entry. Temporary by default; persisted only to prevent data loss.
public struct Snippet: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID

    public var title: String
    public var titleSource: SnippetTitleSource

    public var mainEditor: EditorDocument
    public var splitEditor: EditorDocument?
    public var splitOrientation: SplitOrientation?

    public var isPinned: Bool

    public var createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date?

    /// When an unpinned snippet expires (default policy: 7 days after last change).
    public var expiresAt: Date?
    /// When the snippet was soft-deleted into Recovery, if applicable.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        titleSource: SnippetTitleSource = .automatic,
        mainEditor: EditorDocument,
        splitEditor: EditorDocument? = nil,
        splitOrientation: SplitOrientation? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        expiresAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.titleSource = titleSource
        self.mainEditor = mainEditor
        self.splitEditor = splitEditor
        self.splitOrientation = splitOrientation
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.expiresAt = expiresAt
        self.deletedAt = deletedAt
    }
}
