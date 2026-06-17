import Foundation

/// Transient UI state restored on launch. Stored as `app_state.json`.
public struct AppState: Codable, Sendable, Equatable {
    public var selectedSnippetId: UUID?

    public var sidebarVisible: Bool
    public var sidebarWidth: Double
    public var sidebarCollapsed: Bool

    public var windowFrame: WindowFrame?

    public var commandPaletteRecentCommands: [CommandId]

    public init(
        selectedSnippetId: UUID? = nil,
        sidebarVisible: Bool = true,
        sidebarWidth: Double = 240,
        sidebarCollapsed: Bool = false,
        windowFrame: WindowFrame? = nil,
        commandPaletteRecentCommands: [CommandId] = []
    ) {
        self.selectedSnippetId = selectedSnippetId
        self.sidebarVisible = sidebarVisible
        self.sidebarWidth = sidebarWidth
        self.sidebarCollapsed = sidebarCollapsed
        self.windowFrame = windowFrame
        self.commandPaletteRecentCommands = commandPaletteRecentCommands
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedSnippetId = try c.decodeIfPresent(UUID.self, forKey: .selectedSnippetId)
        sidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 240
        sidebarCollapsed = try c.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) ?? false
        windowFrame = try c.decodeIfPresent(WindowFrame.self, forKey: .windowFrame)
        commandPaletteRecentCommands =
            try c.decodeIfPresent([CommandId].self, forKey: .commandPaletteRecentCommands) ?? []
    }

    /// State used on first launch or when no valid `app_state.json` exists.
    public static let `default` = AppState()
}
