import AppKit
import Foundation
import Observation
import os
import SharedModels
import SharedUtilities
import Storage
import SwiftUI

/// Owns persistence and the restored UI state for the lifetime of the app.
///
/// Built once at launch. If storage fails to initialize, the app still runs
/// with default state and surfaces `initializationError` rather than crashing —
/// the reliability requirement forbids losing the session to a setup error.
@MainActor
@Observable
final class AppModel {
    private(set) var settings: SharedModels.Settings
    private(set) var appState: AppState
    private(set) var initializationError: Error?

    /// In-memory editor content. Persisted to disk in Milestone 3.
    var editorText: String = ""

    @ObservationIgnored private let stack: StorageStack?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var appStateSaveTask: Task<Void, Never>?
    @ObservationIgnored private let log = AppLog.make("app.model")

    /// `directories` is injectable for tests/previews; production resolves the default container.
    init(directories: AppDirectories? = nil) {
        do {
            let resolved = try directories ?? AppDirectories.makeDefault()
            let stack = try StorageStack(directories: resolved)
            let restored = stack.restore()
            self.stack = stack
            self.settings = restored.settings
            self.appState = restored.appState
            log.info("Restored state on launch")
        } catch {
            self.stack = nil
            self.settings = .default
            self.appState = .default
            self.initializationError = error
            log.error("Storage initialization failed: \(error.localizedDescription, privacy: .public)")
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushAppState() }
        }
    }

    var storageIsHealthy: Bool { stack != nil }

    /// SwiftUI color scheme derived from the appearance preference.
    var colorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Window

    /// Connects the SwiftUI-created window: restores its saved frame and tracks
    /// future geometry changes.
    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        if let frame = appState.windowFrame {
            window.setFrame(
                NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                display: true
            )
        }

        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.captureWindowFrame() }
            }
        }
    }

    private func captureWindowFrame() {
        guard let window else { return }
        let frame = window.frame
        appState.windowFrame = WindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
        scheduleAppStateSave()
    }

    // MARK: - Persistence

    /// Debounced save of UI state; frequent window events coalesce into one write.
    private func scheduleAppStateSave() {
        appStateSaveTask?.cancel()
        appStateSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushAppState()
        }
    }

    /// Writes UI state immediately (on quit, or to flush a pending debounce).
    private func flushAppState() {
        appStateSaveTask?.cancel()
        guard let stack else { return }
        do {
            try stack.saveAppState(appState)
        } catch {
            log.error("Failed to persist app state: \(error.localizedDescription, privacy: .public)")
        }
    }
}
