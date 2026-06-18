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
                .toolbar {
                    topToolbar(model: model)
                }
        }
        .frame(minWidth: 560, minHeight: 360)
        .background(WindowAccessor { model.attach(window: $0) })
        .overlay(alignment: .bottom) {
            if let error = model.initializationError {
                storageWarning(error)
            } else if let status = model.transientStatus {
                banner(status)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.transientStatus)
        .onAppear {
            columnVisibility = model.appState.sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: model.appState.sidebarVisible) { _, visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, v in
            model.setSidebarVisible(v != .detailOnly)
        }
        .sheet(isPresented: $model.isRecoveryPresented) {
            RecoveryView()
                .environment(model)
        }
        .background {
            keyboardShortcuts
        }
    }

    /// The detail pane: a single editor, or the main + split editors arranged by
    /// the current snippet's split orientation with a draggable divider.
    @ViewBuilder
    private func editorArea(model: AppModel) -> some View {
        let main = EditorPane(target: .main)
        let split = EditorPane(target: .split)

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

    /// The application's top toolbar, right of the "Snip" title (FR-20): New
    /// Snippet and Pin/Unpin, plus the existing Recovery entry point. Snippet-
    /// scoped buttons disable when there is no selection; New Snippet disables at
    /// the snippet cap (FR-21).
    @ToolbarContentBuilder
    private func topToolbar(model: AppModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                model.createSnippet()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help(
                model.canCreateSnippet ? "New Snippet" : "Snippet limit reached (\(Limits.maxActiveSnippets))"
            )
            .disabled(!model.canCreateSnippet)

            let isPinned = model.currentSnippet?.isPinned ?? false
            Button {
                if let id = model.currentSnippet?.id { model.togglePin(id) }
            } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin")
            }
            .help(isPinned ? "Unpin" : "Pin")
            .disabled(model.currentSnippet == nil)

            Button {
                model.showRecovery()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("Recovery")
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
            Button("") { model.findFocusedEditor() }
                .keyboardShortcut("f", modifiers: .command)
            ForEach(1..<10, id: \.self) { index in
                Button("") {
                    let i = index - 1
                    if i < model.snippets.count {
                        model.selectSnippet(model.snippets[i].id, focusEditor: true)
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
