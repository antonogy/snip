import SharedModels
import SwiftUI

/// The per-editor toolbar (FR-19): in-editor search, Format Code, and a language
/// switcher, all scoped to a single editor (`target`). Each editor in a split
/// renders its own, keeping independent language and search state.
struct EditorToolbar: View {
    let target: EditorTarget
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.showFind(target)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Find in this editor (⌘F)")

            Spacer(minLength: 0)

            languagePicker
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var languagePicker: some View {
        switch target {
        case .main:
            LanguagePicker(
                caption: nil,
                language: model.mainLanguage,
                isAuto: model.mainLanguageIsAuto,
                onSelect: { model.selectMainLanguage($0) },
                onAuto: { model.restoreMainAutoDetect() }
            )
        case .split:
            LanguagePicker(
                caption: nil,
                language: model.splitLanguage,
                isAuto: model.splitLanguageIsAuto,
                onSelect: { model.selectSplitLanguage($0) },
                onAuto: { model.restoreSplitAutoDetect() }
            )
        }
    }
}
