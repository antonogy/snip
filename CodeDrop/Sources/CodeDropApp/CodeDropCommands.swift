import SwiftUI

/// Menu-bar commands for the split editor. The full command palette (FR-6) lands
/// in a later milestone; these expose Milestone 5's split actions with keyboard
/// shortcuts in a `View` menu.
struct CodeDropCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Editor") {
            Button("Format Code") { model.formatFocusedEditor() }
                .keyboardShortcut("f", modifiers: [.control, .option])
                .disabled(!model.canFormat)
        }
        CommandMenu("View") {
            Button("Split Right") { model.splitRight() }
                .keyboardShortcut("\\", modifiers: .command)
            Button("Split Down") { model.splitDown() }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
            Divider()
            Button("Close Split") { model.closeSplit() }
                .keyboardShortcut("\\", modifiers: [.command, .option])
                .disabled(!model.hasSplit)
            Divider()
            Button("Recovery…") { model.showRecovery() }
        }
    }
}
