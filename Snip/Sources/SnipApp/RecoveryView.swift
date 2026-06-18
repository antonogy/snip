import SharedModels
import SwiftUI

/// A user-initiated sheet listing deleted and expired snippets (FR-11). Each row can
/// be restored; permanent removal happens automatically after the retention window.
struct RecoveryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery")
                .font(.headline)

            if model.recoveryItems.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No deleted snippets.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                List(model.recoveryItems) { item in
                    RecoveryRow(item: item) { model.restoreSnippet(item.snippetId) }
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380, height: 420)
    }
}

private struct RecoveryRow: View {
    let item: RecoveryItem
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Restore", action: onRestore)
        }
        .padding(.vertical, 2)
    }

    private var caption: String {
        let deleted = item.deletedAt.formatted(.relative(presentation: .named))
        let purges = item.purgeAfter.formatted(.relative(presentation: .named))
        return "deleted \(deleted) · purges \(purges)"
    }
}
