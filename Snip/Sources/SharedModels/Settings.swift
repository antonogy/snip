import Foundation

/// User preferences. Stored as `settings.json`.
public struct Settings: Codable, Sendable, Equatable {
    /// Days after last modification before an unpinned snippet expires.
    public var expirationDays: Int
    /// Days a deleted/expired snippet is retained in Recovery before purge.
    public var deletionGracePeriodDays: Int

    public var appearanceMode: AppearanceMode
    public var wordWrapEnabled: Bool

    public var iCloudSyncEnabled: Bool

    public init(
        expirationDays: Int = 7,
        deletionGracePeriodDays: Int = 30,
        appearanceMode: AppearanceMode = .system,
        wordWrapEnabled: Bool = true,
        iCloudSyncEnabled: Bool = false
    ) {
        self.expirationDays = expirationDays
        self.deletionGracePeriodDays = deletionGracePeriodDays
        self.appearanceMode = appearanceMode
        self.wordWrapEnabled = wordWrapEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
    }

    /// Defaults used on first launch or when no valid `settings.json` exists.
    public static let `default` = Settings()
}
