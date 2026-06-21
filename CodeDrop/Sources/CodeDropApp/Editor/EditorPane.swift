import SharedModels
import SwiftUI

/// One editor with its own toolbar stacked above it (FR-19). `target` selects
/// which editor's content and language this pane is bound to (main or split).
struct EditorPane: View {
    let target: EditorTarget
    @Environment(AppModel.self) private var model
    @State private var cursorLine = 1
    @State private var cursorColumn = 1

    var body: some View {
        @Bindable var model = model
        CodeDropEditorView(
            text: target == .main ? $model.editorText : $model.splitEditorText,
            wordWrap: model.settings.wordWrapEnabled,
            language: target == .main ? model.mainLanguage : model.splitLanguage,
            onFocus: { model.focusEditor(target, $0) },
            onMake: { model.register(target, $0) },
            onContentLimitExceeded: {
                model.flashStatus("Content limit reached (\(Limits.maxEditorCharacters) characters).")
            },
            onCursorMove: { line, col in
                cursorLine = line
                cursorColumn = col
            },
            autoFocusOnInstall: target == .main
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                EditorToolbar(target: target)
                Divider()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                EditorStatusBar(line: cursorLine, column: cursorColumn)
            }
        }
    }
}
