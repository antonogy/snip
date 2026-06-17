import SharedModels
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedId: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            List(Array(model.snippets.enumerated()), id: \.element.id, selection: $selectedId) { index, snippet in
                SnippetCard(snippet: snippet, index: index)
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
    }
}

struct SnippetCard: View {
    let snippet: Snippet
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snippet.title)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if snippet.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Text(snippet.mainEditor.language.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}
