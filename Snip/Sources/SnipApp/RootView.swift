import SharedModels
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 240, max: 400)
        } detail: {
            editorArea(model: model)
                .frame(minWidth: 400, minHeight: 300)
                .toolbar { languageToolbar(model: model) }
        }
        .frame(minWidth: 560, minHeight: 360)
        .background(WindowAccessor { model.attach(window: $0) })
        .overlay(alignment: .bottom) {
            if let error = model.initializationError {
                storageWarning(error)
            } else if let formatError = model.formatError {
                banner(formatError)
            }
        }
        .onAppear {
            columnVisibility = model.appState.sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: model.appState.sidebarVisible) { _, visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, v in
            model.setSidebarVisible(v != .detailOnly)
        }
        .background {
            keyboardShortcuts
        }
    }

    /// The detail pane: a single editor, or the main + split editors arranged by
    /// the current snippet's split orientation with a draggable divider.
    @ViewBuilder
    private func editorArea(model: AppModel) -> some View {
        @Bindable var model = model
        let main = SnipEditorView(
            text: $model.editorText,
            wordWrap: model.settings.wordWrapEnabled,
            language: model.mainLanguage,
            onFocus: { model.focusEditor(.main, $0) }
        )
        let split = SnipEditorView(
            text: $model.splitEditorText,
            wordWrap: model.settings.wordWrapEnabled,
            language: model.splitLanguage,
            onFocus: { model.focusEditor(.split, $0) }
        )

        switch model.splitOrientation {
        case .none:
            main
        case .horizontal:
            HSplitView {
                main.frame(minWidth: 200)
                split.frame(minWidth: 200)
            }
        case .vertical:
            VSplitView {
                main.frame(minHeight: 120)
                split.frame(minHeight: 120)
            }
        }
    }

    /// Language menu(s) for the detail toolbar: one for a single editor, or a
    /// labeled pair when a split is open (each editor's language is independent).
    @ToolbarContentBuilder
    private func languageToolbar(model: AppModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if model.currentSnippet != nil {
                LanguagePicker(
                    caption: model.hasSplit ? "Main" : nil,
                    language: model.mainLanguage,
                    isAuto: model.mainLanguageIsAuto,
                    onSelect: { model.selectMainLanguage($0) },
                    onAuto: { model.restoreMainAutoDetect() }
                )
                if model.hasSplit {
                    LanguagePicker(
                        caption: "Split",
                        language: model.splitLanguage,
                        isAuto: model.splitLanguageIsAuto,
                        onSelect: { model.selectSplitLanguage($0) },
                        onAuto: { model.restoreSplitAutoDetect() }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Group {
            Button("") { model.createSnippet() }
                .keyboardShortcut("n", modifiers: .command)
            Button("") {
                if let id = model.currentSnippet?.id { model.deleteSnippet(id) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Button("") { model.toggleSidebar() }
                .keyboardShortcut("b", modifiers: .command)
            ForEach(1..<10, id: \.self) { index in
                Button("") {
                    let i = index - 1
                    if i < model.snippets.count {
                        model.selectSnippet(model.snippets[i].id)
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func storageWarning(_ error: Error) -> some View {
        banner("Storage unavailable — changes won't be saved.")
    }

    /// A transient, non-modal status capsule pinned to the bottom of the editor.
    @ViewBuilder
    private func banner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
        .transition(.opacity)
    }
}
