import SwiftUI

/// Foundation-milestone placeholder UI.
///
/// Milestone 1 only proves the app launches and restores state; the editor,
/// sidebar, and command palette arrive in later milestones and will replace
/// this view.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Snip")
                .font(.title2.weight(.semibold))

            if let error = model.initializationError {
                Text("Storage unavailable — running with defaults.")
                    .foregroundStyle(.red)
                Text(String(describing: error))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Foundation ready · state restored")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 360)
        .background(WindowAccessor { model.attach(window: $0) })
    }
}
