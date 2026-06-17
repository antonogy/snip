import SharedModels
import SwiftUI

/// Toolbar menu for viewing and switching an editor's language (FR-14).
///
/// Shows the current language; "Auto Detect" is checked while the language is
/// being detected automatically, and picking a concrete language pins it
/// (disabling auto-detection). With a split open, `caption` distinguishes the
/// "Main" and "Split" menus.
struct LanguagePicker: View {
    var caption: String?
    var language: CodeLanguage
    var isAuto: Bool
    var onSelect: (CodeLanguage) -> Void
    var onAuto: () -> Void

    var body: some View {
        Menu {
            menuRow("Auto Detect", selected: isAuto, action: onAuto)
            Divider()
            ForEach(CodeLanguage.allCases, id: \.self) { lang in
                menuRow(lang.displayName, selected: !isAuto && lang == language) {
                    onSelect(lang)
                }
            }
        } label: {
            if let caption {
                Text("\(caption): \(language.displayName)")
            } else {
                Text(language.displayName)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(isAuto ? "Auto-detected language" : "Language set manually")
    }

    @ViewBuilder
    private func menuRow(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            // A checkmark image marks the active choice; unselected rows use a
            // plain label, which macOS aligns under the checked one.
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
