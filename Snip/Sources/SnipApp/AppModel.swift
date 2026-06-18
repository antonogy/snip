import AppKit
import Formatting
import Foundation
import Observation
import os
import SharedModels
import SharedUtilities
import Storage
import SwiftUI

/// Which editor a content-targeted command (e.g. Format) acts on.
enum EditorTarget {
    case main
    case split
}

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

    var splitEditorText: String = "" {
        didSet {
            guard !isLoadingContent, splitEditorText != oldValue else { return }
            scheduleSplitSave()
        }
    }

    /// Which editor last gained focus; targets the Format command. Forced back to
    /// `.main` whenever there is no split (see `effectiveFocusTarget`).
    private(set) var focusedTarget: EditorTarget = .main

    /// Transient, user-facing formatting error message. Auto-clears after a few
    /// seconds; drives a non-modal banner in `RootView`.
    private(set) var formatError: String?

    /// Whether the current snippet has a split editor.
    var hasSplit: Bool { currentSnippet?.splitEditor != nil }

    /// Orientation of the current snippet's split, or `nil` when there is no split.
    var splitOrientation: SplitOrientation? {
        currentSnippet?.splitEditor != nil ? currentSnippet?.splitOrientation : nil
    }

    @ObservationIgnored private let stack: StorageStack?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var appStateSaveTask: Task<Void, Never>?
    @ObservationIgnored private var editorSaveTask: Task<Void, Never>?
    @ObservationIgnored private var splitSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadingContent = false
    @ObservationIgnored private weak var focusedTextView: HighlightingTextView?
    @ObservationIgnored private let formatter = CodeFormatter()
    @ObservationIgnored private var isFormatting = false
    @ObservationIgnored private var formatErrorTask: Task<Void, Never>?
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
                    let splitText = try target.splitEditor.map { try stack.loadSnippetContent(for: $0) } ?? ""
                    self.currentSnippet = target
                    self.isLoadingContent = true
                    self.editorText = text
                    self.splitEditorText = splitText
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
                self?.flushSplitContent()
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
        flushSplitContent()
        do {
            let new = try stack.createSnippet()
            refreshSnippets()
            currentSnippet = snippets.first(where: { $0.id == new.id }) ?? new
            appState.selectedSnippetId = new.id
            isLoadingContent = true
            editorText = ""
            splitEditorText = ""
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
        flushSplitContent()
        do {
            let text = try stack.loadSnippetContent(for: snippet.mainEditor)
            let splitText = try snippet.splitEditor.map { try stack.loadSnippetContent(for: $0) } ?? ""
            currentSnippet = snippet
            appState.selectedSnippetId = id
            isLoadingContent = true
            editorText = text
            splitEditorText = splitText
            isLoadingContent = false
            scheduleAppStateSave()
        } catch {
            log.error("Failed to load snippet content: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteSnippet(_ id: UUID) {
        guard let stack else { return }
        if currentSnippet?.id == id {
            flushEditorContent()
            flushSplitContent()
        }
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

    // MARK: - Split editor

    /// Splits the current snippet into a left/right pair (or re-orients an existing split).
    func splitRight() { setSplit(.horizontal) }

    /// Splits the current snippet into a top/bottom pair (or re-orients an existing split).
    func splitDown() { setSplit(.vertical) }

    private func setSplit(_ orientation: SplitOrientation) {
        guard let stack, let id = currentSnippet?.id else { return }
        flushSplitContent()
        do {
            let updated = try stack.setSplit(snippetId: id, orientation: orientation)
            let splitText = try updated.splitEditor.map { try stack.loadSnippetContent(for: $0) } ?? ""
            currentSnippet = updated
            isLoadingContent = true
            splitEditorText = splitText
            isLoadingContent = false
            refreshSnippets()
        } catch {
            log.error("Failed to set split: \(error.localizedDescription, privacy: .public)")
        }
    }

    func closeSplit() {
        guard let stack, let id = currentSnippet?.id, hasSplit else { return }
        do {
            let updated = try stack.closeSplit(snippetId: id)
            splitSaveTask?.cancel()
            focusedTarget = .main
            currentSnippet = updated
            isLoadingContent = true
            splitEditorText = ""
            isLoadingContent = false
            refreshSnippets()
        } catch {
            log.error("Failed to close split: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Language

    /// Convenience accessors for the toolbar pickers.
    var mainLanguage: CodeLanguage { currentSnippet?.mainEditor.language ?? .plainText }
    var mainLanguageIsAuto: Bool { (currentSnippet?.mainEditor.languageMode ?? .auto) == .auto }
    var splitLanguage: CodeLanguage { currentSnippet?.splitEditor?.language ?? .plainText }
    var splitLanguageIsAuto: Bool { (currentSnippet?.splitEditor?.languageMode ?? .auto) == .auto }

    /// Manually pins the main editor's language, disabling auto-detection (FR-14).
    func selectMainLanguage(_ language: CodeLanguage) {
        applyMainLanguage(language, mode: .manual)
    }

    /// Restores auto-detection for the main editor and re-runs it immediately.
    func restoreMainAutoDetect() {
        applyMainLanguage(mainLanguage, mode: .auto)
        detectMainLanguage()
    }

    /// Manually pins the split editor's language, disabling auto-detection (FR-14).
    func selectSplitLanguage(_ language: CodeLanguage) {
        applySplitLanguage(language, mode: .manual)
    }

    /// Restores auto-detection for the split editor and re-runs it immediately.
    func restoreSplitAutoDetect() {
        applySplitLanguage(splitLanguage, mode: .auto)
        detectSplitLanguage()
    }

    /// Auto-detects the main editor's language when it is in auto mode. An empty
    /// editor clears any manual override and returns to Auto Detect (FR-3).
    private func detectMainLanguage() {
        guard !isLoadingContent, let snippet = currentSnippet else { return }
        let editor = snippet.mainEditor
        if editorText.isEmpty {
            if editor.languageMode != .auto || editor.language != .plainText {
                applyMainLanguage(.plainText, mode: .auto)
            }
            return
        }
        guard editor.languageMode == .auto else { return }
        let detected = LanguageDetector.detect(editorText)
        if detected != editor.language {
            applyMainLanguage(detected, mode: .auto)
        }
    }

    /// Auto-detects the split editor's language when it is in auto mode.
    private func detectSplitLanguage() {
        guard !isLoadingContent, let snippet = currentSnippet, let editor = snippet.splitEditor else {
            return
        }
        if splitEditorText.isEmpty {
            if editor.languageMode != .auto || editor.language != .plainText {
                applySplitLanguage(.plainText, mode: .auto)
            }
            return
        }
        guard editor.languageMode == .auto else { return }
        let detected = LanguageDetector.detect(splitEditorText)
        if detected != editor.language {
            applySplitLanguage(detected, mode: .auto)
        }
    }

    private func applyMainLanguage(_ language: CodeLanguage, mode: LanguageMode) {
        guard let stack, let id = currentSnippet?.id else { return }
        do {
            let updated = try stack.setMainLanguage(snippetId: id, language: language, mode: mode)
            currentSnippet = updated
            refreshSnippets()
        } catch {
            log.error("Failed to set main language: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applySplitLanguage(_ language: CodeLanguage, mode: LanguageMode) {
        guard let stack, let id = currentSnippet?.id, hasSplit else { return }
        do {
            let updated = try stack.setSplitLanguage(snippetId: id, language: language, mode: mode)
            currentSnippet = updated
            refreshSnippets()
        } catch {
            log.error("Failed to set split language: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Formatting

    /// Records which editor gained focus and a reference to its text view, so
    /// `formatFocusedEditor()` knows where to read from and write back to.
    func focusEditor(_ target: EditorTarget, _ textView: HighlightingTextView) {
        focusedTarget = target
        focusedTextView = textView
    }

    /// The editor the Format command acts on. Falls back to `.main` when there
    /// is no split, regardless of any stale focus.
    private var effectiveFocusTarget: EditorTarget { hasSplit ? focusedTarget : .main }

    /// Language of the editor the Format command would act on.
    private var focusedLanguage: CodeLanguage {
        effectiveFocusTarget == .main ? mainLanguage : splitLanguage
    }

    /// Whether "Format Code" is available right now (drives the menu's enabled
    /// state). Plain Text has no formatter.
    var canFormat: Bool { currentSnippet != nil && focusedLanguage != .plainText }

    /// Formats the focused editor (FR-7). Runs the formatter off the main actor,
    /// then replaces the content through the undo-registering path. Surfaces a
    /// transient banner on failure. Manual only — never triggered automatically.
    func formatFocusedEditor() {
        guard !isFormatting, currentSnippet != nil else { return }
        let target = effectiveFocusTarget
        let language = focusedLanguage
        guard language != .plainText else {
            setFormatError(FormatterError.unsupportedLanguage(.plainText).userFacingMessage)
            return
        }
        let source = focusedTextView?.string ?? (target == .main ? editorText : splitEditorText)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isFormatting = true
        Task { [weak self, formatter] in
            defer { self?.isFormatting = false }
            do {
                let result = try await formatter.format(source, language: language)
                guard let self else { return }
                if let textView = self.focusedTextView {
                    textView.replaceAllText(result)
                } else if target == .main {
                    self.editorText = result
                } else {
                    self.splitEditorText = result
                }
            } catch {
                let message =
                    (error as? FormatterError)?.userFacingMessage ?? "Formatting failed."
                self?.setFormatError(message)
            }
        }
    }

    /// Shows a transient, non-modal error message that clears itself after a few
    /// seconds (matching the product's "non-blocking" principle).
    private func setFormatError(_ message: String) {
        formatErrorTask?.cancel()
        formatError = message
        log.error("Format failed: \(message, privacy: .public)")
        formatErrorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.formatError = nil
        }
    }

    // MARK: - Editor Persistence

    private func scheduleEditorSave() {
        editorSaveTask?.cancel()
        editorSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_000))
            guard !Task.isCancelled else { return }
            self?.flushEditorContent()
            self?.detectMainLanguage()
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

    private func scheduleSplitSave() {
        splitSaveTask?.cancel()
        splitSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_000))
            guard !Task.isCancelled else { return }
            self?.flushSplitContent()
            self?.detectSplitLanguage()
        }
    }

    private func flushSplitContent() {
        splitSaveTask?.cancel()
        guard let stack, let doc = currentSnippet?.splitEditor else { return }
        do {
            try stack.saveEditorContent(splitEditorText, for: doc)
        } catch {
            log.error("Failed to autosave split content: \(error.localizedDescription, privacy: .public)")
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
