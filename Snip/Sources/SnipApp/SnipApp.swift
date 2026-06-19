import SwiftUI

/// The SwiftUI app. A single, unique `Window` satisfies the single-window
/// constraint; appearance follows the restored settings.
struct SnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
        }
        .commands {
            SnipCommands(model: model)
        }
    }
}
