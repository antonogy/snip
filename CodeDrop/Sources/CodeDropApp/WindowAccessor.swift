import AppKit
import SwiftUI

/// Bridges to the underlying `NSWindow` that SwiftUI creates, invoking `onWindow`
/// once the view is installed in a window. Used to restore and track window frame.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
