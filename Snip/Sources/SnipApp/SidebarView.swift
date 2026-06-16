import SharedModels
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedId: UUID?

    var body: some View {
        List(model.snippets, id: \.id, selection: $selectedId) { snippet in
            SnippetCard(snippet: snippet)
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
        }
    }
}

struct SnippetCard: View {
    let snippet: Snippet

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
                Text(snippet.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
