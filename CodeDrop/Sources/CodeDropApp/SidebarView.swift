import SharedModels
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedId: UUID?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollViewReader { proxy in
                List(Array(model.snippets.enumerated()), id: \.element.id, selection: $selectedId) { index, snippet in
                    SnippetCard(snippet: snippet, index: index, preview: model.preview(for: snippet.id))
                        .tag(snippet.id)
                        .contextMenu {
                            Button(snippet.isPinned ? "Unpin" : "Pin") {
                                model.togglePin(snippet.id)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                model.deleteSnippet(snippet.id)
                            }
                        }
                }
                .listStyle(.sidebar)
                // Reserve space at the bottom so the last row is never hidden
                // behind the New Snippet button.
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 44)
                }
                // Animate row insert / delete / pin-reorder. Keyed on the ordered
                // identities so reorders (which don't change the count) animate too.
                .animation(.default, value: model.snippets.map(\.id))
                .onAppear { selectedId = model.currentSnippet?.id }
                .onChange(of: selectedId) { _, id in
                    if let id, id != model.currentSnippet?.id {
                        model.selectSnippet(id)
                    }
                }
                .onChange(of: model.currentSnippet?.id) { _, id in
                    if id != selectedId { selectedId = id }
                    // When a new snippet is created it lands at snippets[0].
                    // SwiftUI's automatic scroll-to-selected doesn't account for the
                    // title-bar safe area, leaving the top of the first row clipped.
                    // Explicit scrollTo with .top uses the safe-area-adjusted origin.
                    if let id, model.snippets.first?.id == id {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }

            Button {
                model.createSnippet()
            } label: {
                Label("New Snippet", systemImage: "plus.circle.fill")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help(
                model.canCreateSnippet
                    ? "New Snippet (⌘N)" : "Snippet limit reached (\(Limits.maxActiveSnippets))"
            )
            .disabled(!model.canCreateSnippet)
            .padding(.leading, 12)
            .padding(.bottom, 10)
        }
    }
}

struct SnippetCard: View {
    let snippet: Snippet
    let index: Int
    /// First few content lines (FR-2 Smart Titles), empty for an empty snippet.
    let preview: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                contentPreview
                Spacer(minLength: 0)
                if snippet.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Text(snippet.mainEditor.language.displayName.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
                if snippet.splitEditor != nil {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Split")
                }
                Spacer(minLength: 0)
                if index < 9 {
                    Text("\u{2318}\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Up to three content lines in equal-weight monospace, or a dim placeholder
    /// when the snippet has no content yet.
    @ViewBuilder
    private var contentPreview: some View {
        if preview.isEmpty {
            Text("Empty")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(preview.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}
