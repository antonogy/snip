import AppKit
import Foundation
import Observation
import os
import SharedModels
import SharedUtilities
import Storage
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private(set) var settings: SharedModels.Settings
    private(set) var appState: AppState
    private(set) var initializationError: Error?

    private(set) var snippets: [Snippet] = []
    private(set) var currentSnippet: Snippet?

    var editorText: String = "" {
        didSet {
            guard !isLoadingContent, editorText != oldValue else { return }
            scheduleEditorSave()
        }
    }

    @ObservationIgnored private let stack: StorageStack?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var appStateSaveTask: Task<Void, Never>?
    @ObservationIgnored private var editorSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadingContent = false
    @ObservationIgnored private let log = AppLog.make("app.model")

    init(directories: AppDirectories? = nil) {
        do {
            let resolved = try directories ?? AppDirectories.makeDefault()
            let stack = try StorageStack(directories: resolved)
            let restored = stack.restore()
            self.stack = stack
            self.settings = restored.settings
            self.appState = restored.appState

            // Load snippet list; bootstrap on first launch. Nested catch so that
            // a failure here doesn't prevent the app from launching with a healthy stack.
            do {
                var list = try stack.listSnippets()
                if list.isEmpty {
                    _ = try stack.loadOrBootstrap()
                    list = try stack.listSnippets()
                }
                self.snippets = list

                let target =
                    list.first(where: { $0.id == restored.appState.selectedSnippetId }) ?? list.first
                if let target {
                    let text = try stack.loadSnippetContent(for: target.mainEditor)
                    self.currentSnippet = target
                    self.isLoadingContent = true
                    self.editorText = text
                    self.isLoadingContent = false
                }
                log.info("Restored state on launch, \(list.count) snippet(s)")
            } catch {
                log.error("Failed to restore snippets: \(error.localizedDescription, privacy: .public)")
            }

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
            MainActor.assumeIsolated {
                self?.flushEditorContent()
                self?.flushAppState()
            }
        }
    }

    var storageIsHealthy: Bool { stack != nil }

    var colorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Window

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

    // MARK: - Snippet operations

    func createSnippet() {
        guard let stack else { return }
        flushEditorContent()
        do {
            let new = try stack.createSnippet()
            refreshSnippets()
            currentSnippet = snippets.first(where: { $0.id == new.id }) ?? new
            appState.selectedSnippetId = new.id
            isLoadingContent = true
            editorText = ""
            isLoadingContent = false
            scheduleAppStateSave()
        } catch {
            log.error("Failed to create snippet: \(error.localizedDescription, privacy: .public)")
        }
    }

    func selectSnippet(_ id: UUID) {
        guard id != currentSnippet?.id else { return }
        guard let stack, let snippet = snippets.first(where: { $0.id == id }) else { return }
        flushEditorContent()
        do {
            let text = try stack.loadSnippetContent(for: snippet.mainEditor)
            currentSnippet = snippet
            appState.selectedSnippetId = id
            isLoadingContent = true
            editorText = text
            isLoadingContent = false
            scheduleAppStateSave()
        } catch {
            log.error("Failed to load snippet content: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteSnippet(_ id: UUID) {
        guard let stack else { return }
        if currentSnippet?.id == id { flushEditorContent() }
        do {
            try stack.deleteSnippet(id: id, gracePeriodDays: settings.deletionGracePeriodDays)
            refreshSnippets()
            if currentSnippet == nil {
                if let first = snippets.first {
                    selectSnippet(first.id)
                } else {
                    createSnippet()
                }
            }
        } catch {
            log.error("Failed to delete snippet: \(error.localizedDescription, privacy: .public)")
        }
    }

    func togglePin(_ id: UUID) {
        guard let stack, let target = snippets.first(where: { $0.id == id }) else { return }
        do {
            try stack.setSnippetPinned(id: id, isPinned: !target.isPinned)
            refreshSnippets()
        } catch {
            log.error("Failed to toggle pin: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleSidebar() {
        setSidebarVisible(!appState.sidebarVisible)
    }

    func setSidebarVisible(_ visible: Bool) {
        guard visible != appState.sidebarVisible else { return }
        appState.sidebarVisible = visible
        scheduleAppStateSave()
    }

    // MARK: - Editor Persistence

    private func scheduleEditorSave() {
        editorSaveTask?.cancel()
        editorSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_000))
            guard !Task.isCancelled else { return }
            self?.flushEditorContent()
        }
    }

    private func flushEditorContent() {
        editorSaveTask?.cancel()
        guard let stack, let doc = currentSnippet?.mainEditor else { return }
        do {
            try stack.saveEditorContent(editorText, for: doc)
        } catch {
            log.error("Failed to autosave editor content: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Persistence

    private func scheduleAppStateSave() {
        appStateSaveTask?.cancel()
        appStateSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushAppState()
        }
    }

    private func flushAppState() {
        appStateSaveTask?.cancel()
        guard let stack else { return }
        do {
            try stack.saveAppState(appState)
        } catch {
            log.error("Failed to persist app state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private helpers

    private func refreshSnippets() {
        guard let stack else { return }
        do {
            snippets = try stack.listSnippets()
            // Re-sync currentSnippet; becomes nil if it was just deleted.
            if let current = currentSnippet {
                currentSnippet = snippets.first(where: { $0.id == current.id })
            }
        } catch {
            log.error("Failed to refresh snippet list: \(error.localizedDescription, privacy: .public)")
        }
    }
}
