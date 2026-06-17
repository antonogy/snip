import SwiftUI
import SharedModels

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
        }
        .frame(minWidth: 560, minHeight: 360)
        .background(WindowAccessor { model.attach(window: $0) })
        .overlay(alignment: .bottom) {
            if let error = model.initializationError {
                storageWarning(error)
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
        let main = SnipEditorView(text: $model.editorText, wordWrap: model.settings.wordWrapEnabled)
        let split = SnipEditorView(text: $model.splitEditorText, wordWrap: model.settings.wordWrapEnabled)

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
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Storage unavailable — changes won't be saved.")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }
}
