import Foundation

/// Transient UI state restored on launch. Stored as `app_state.json`.
public struct AppState: Codable, Sendable, Equatable {
    public var selectedSnippetId: UUID?

    public var sidebarVisible: Bool
    public var sidebarWidth: Double

    public var windowFrame: WindowFrame?

    public var commandPaletteRecentCommands: [CommandId]

    public init(
        selectedSnippetId: UUID? = nil,
        sidebarVisible: Bool = true,
        sidebarWidth: Double = 240,
        windowFrame: WindowFrame? = nil,
        commandPaletteRecentCommands: [CommandId] = []
    ) {
        self.selectedSnippetId = selectedSnippetId
        self.sidebarVisible = sidebarVisible
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
        self.commandPaletteRecentCommands = commandPaletteRecentCommands
    }

    /// State used on first launch or when no valid `app_state.json` exists.
    public static let `default` = AppState()
}
