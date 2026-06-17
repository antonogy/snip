import SwiftUI
import SharedModels

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        let collapsed = model.appState.sidebarCollapsed
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: collapsed ? 82 : 160,
                    ideal: collapsed ? 82 : 240,
                    max: collapsed ? 82 : 400
                )
        } detail: {
            SnipEditorView(text: $model.editorText, wordWrap: model.settings.wordWrapEnabled)
                .frame(minWidth: 400, minHeight: 300)
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbarBackground(.visible, for: .windowToolbar)
        .background(WindowAccessor { model.attach(window: $0) })
        .overlay(alignment: .bottom) {
            if let error = model.initializationError {
                storageWarning(error)
            }
        }
        .onAppear {
            columnVisibility = .all
        }
        .onChange(of: columnVisibility) { _, v in
            if v == .detailOnly {
                columnVisibility = .all
                model.setSidebarCollapsed(true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.toggleSidebar() } label: {
                    Image(systemName: "sidebar.left")
                }
            }
        }
        .background {
            keyboardShortcuts
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
