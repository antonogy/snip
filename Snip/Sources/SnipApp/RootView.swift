import SwiftUI
import SharedModels

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SnipEditorView(text: $model.editorText, wordWrap: model.settings.wordWrapEnabled)
            .frame(minWidth: 520, minHeight: 360)
            .background(WindowAccessor { model.attach(window: $0) })
            .overlay(alignment: .bottom) {
                if let error = model.initializationError {
                    storageWarning(error)
                }
            }
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
