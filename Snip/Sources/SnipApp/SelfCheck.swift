import Foundation
import os
import SharedModels
import SharedUtilities
import Storage

/// Headless startup verification used by `Snip --self-check`.
///
/// Exercises the full launch/restore path (directories → database → migrations
/// → config load) without opening a window, then exits. Lets CI and `swift run`
/// confirm Milestone 1's "launches and restores state" exit criteria.
enum SelfCheck {
    static func run() -> Int32 {
        let log = AppLog.make("selfcheck")
        do {
            let directories = try AppDirectories.makeDefault()
            let stack = try StorageStack(directories: directories)
            try stack.verifySchema()
            let restored = stack.restore()

            log.info("Self-check OK")
            print("snip self-check: OK")
            print("  container:    \(directories.root.path)")
            print("  appearance:   \(restored.settings.appearanceMode.rawValue)")
            print(
                "  sidebar:      visible=\(restored.appState.sidebarVisible) width=\(restored.appState.sidebarWidth)"
            )
            print("  windowFrame:  \(restored.appState.windowFrame.map(String.init(describing:)) ?? "none")")
            return 0
        } catch {
            log.error("Self-check failed: \(error.localizedDescription, privacy: .public)")
            print("snip self-check: FAILED — \(error)")
            return 1
        }
    }
}
