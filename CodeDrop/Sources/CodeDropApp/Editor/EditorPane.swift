import SharedModels
import SwiftUI

/// One editor with its own toolbar stacked above it (FR-19). `target` selects
/// which editor's content and language this pane is bound to (main or split).
struct EditorPane: View {
    let target: EditorTarget
    @Environment(AppModel.self) private var model

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
            autoFocusOnInstall: target == .main
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                EditorToolbar(target: target)
                Divider()
            }
        }
    }
}
