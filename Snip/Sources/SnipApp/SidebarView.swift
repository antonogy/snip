import SharedModels
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedId: UUID?

    var body: some View {
        if model.appState.sidebarCollapsed {
            CollapsedSidebarView()
        } else {
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
}

struct CollapsedSidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(Array(model.snippets.enumerated()), id: \.element.id) { index, snippet in
                CollapsedSnippetItem(
                    snippet: snippet,
                    index: index,
                    isSelected: snippet.id == model.currentSnippet?.id
                )
                .frame(maxWidth: .infinity)
                .onTapGesture { model.selectSnippet(snippet.id) }
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
    }
}

struct CollapsedSnippetItem: View {
    let snippet: Snippet
    let index: Int
    let isSelected: Bool

    var body: some View {
        Image(snippet.mainEditor.language.iconAssetName)
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottomTrailing) {
                if index < 9 {
                    shortcutBadge
                        .padding(2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if snippet.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .frame(width: 44, height: 44)
    }

    private var shortcutBadge: some View {
        Text("\u{2318}\(index + 1)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
//            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
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

extension CodeLanguage {
    var iconAssetName: String {
        switch self {
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .json: return "json"
        case .html: return "htmx"
        case .css: return "css"
        case .sql: return "sql"
        case .swift: return "swift"
        case .python: return "python"
        case .bash: return "bash"
        case .plainText: return "plain_text"
        }
    }
}
