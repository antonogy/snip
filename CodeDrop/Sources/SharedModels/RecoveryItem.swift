import Foundation

/// A snippet that has been soft-deleted or expired and is awaiting permanent
/// purge. Backed by the `recovery_items` table; surfaced to the Recovery UI so a
/// snippet can be restored within the retention window (FR-11).
public struct RecoveryItem: Codable, Sendable, Identifiable, Equatable {
    /// Identity of the recovery row itself (not the snippet).
    public let id: UUID
    /// The snippet this row can restore.
    public let snippetId: UUID
    public let title: String
    /// When the snippet was deleted or expired.
    public let deletedAt: Date
    /// When the snippet becomes eligible for permanent deletion.
    public let purgeAfter: Date

    public init(
        id: UUID,
        snippetId: UUID,
        title: String,
        deletedAt: Date,
        purgeAfter: Date
    ) {
        self.id = id
        self.snippetId = snippetId
        self.title = title
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
    }
}
