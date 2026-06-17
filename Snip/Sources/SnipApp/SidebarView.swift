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
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
                .frame(width: 44, height: 44)
            VStack(spacing: 2) {
                Image(snippet.mainEditor.language.iconAssetName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                if index < 9 {
                    Text("\u{2318}\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: 44, height: 44)
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
        case .javascript: return "javascript-original"
        case .typescript: return "typescript-original"
        case .json: return "json-plain"
        case .html: return "htmx-original"
        case .css: return "css3-plain-wordmark"
        case .sql: return "azuresqldatabase-plain"
        case .swift: return "swift-original"
        case .python: return "python-original"
        case .bash: return "bash-original"
        case .plainText: return "plain-text"
        }
    }
}
