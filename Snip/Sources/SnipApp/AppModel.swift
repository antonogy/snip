import AppKit
import Formatting
import Foundation
import Observation
import SharedModels
import SharedUtilities
import Storage
import SwiftUI
import os

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

    /// Deleted/expired snippets awaiting purge; populated when the Recovery sheet opens.
    private(set) var recoveryItems: [RecoveryItem] = []
    /// Drives the Recovery sheet. Settable so a menu command can present it.
    var isRecoveryPresented = false

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

    /// Transient, user-facing status message (formatting errors, limit hints).
    /// Auto-clears after a few seconds; drives a non-modal banner in `RootView`.
    private(set) var transientStatus: String?

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
    @ObservationIgnored private weak var mainTextView: HighlightingTextView?
    @ObservationIgnored private weak var splitTextView: HighlightingTextView?
    @ObservationIgnored private let formatter = CodeFormatter()
    @ObservationIgnored private var isFormatting = false
    @ObservationIgnored private var statusTask: Task<Void, Never>?
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
                try stack.purgeEmptySnippets()  // FR-1: drop snippets left empty last session
                try stack.purgeExpiredRecoveryItems()  // FR-11: drop items past retention
                try stack.expireStaleSnippets(  // FR-1: move stale unpinned to Recovery
                    expirationDays: restored.settings.expirationDays,
                    gracePeriodDays: restored.settings.deletionGracePeriodDays)
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

    /// Whether a new snippet can be created right now. False once the active
    /// snippet cap is reached; drives the disabled New Snippet button (FR-21).
    var canCreateSnippet: Bool { snippets.count < Limits.maxActiveSnippets }

    func createSnippet() {
        guard let stack else { return }
        guard canCreateSnippet else {
            flashStatus("Snippet limit reached (\(Limits.maxActiveSnippets)). Delete a snippet to make room.")
            return
        }
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
            focusedTarget = .main
            focusMainEditor()  // FR-15: a new snippet focuses the editor.
            scheduleAppStateSave()
        } catch StorageError.snippetLimitReached(let max) {
            flashStatus("Snippet limit reached (\(max)). Delete a snippet to make room.")
        } catch {
            log.error("Failed to create snippet: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Switches the active snippet. `focusEditor` moves keyboard focus into the
    /// editor — passed by explicit ⌘-number jumps so the user can type at once,
    /// but left off for sidebar arrow/click navigation so focus stays in the list.
    func selectSnippet(_ id: UUID, focusEditor: Bool = false) {
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
            if focusEditor { focusMainEditor() }
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

    // MARK: - Recovery

    /// Loads the recovery queue and presents the Recovery sheet.
    func showRecovery() {
        loadRecoveryItems()
        isRecoveryPresented = true
    }

    /// Refreshes the in-memory recovery list from storage.
    func loadRecoveryItems() {
        guard let stack else { return }
        do {
            recoveryItems = try stack.listRecoveryItems()
        } catch {
            log.error("Failed to load recovery items: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Restores a snippet from Recovery and makes it the active selection.
    func restoreSnippet(_ snippetId: UUID) {
        guard let stack else { return }
        do {
            let restored = try stack.restoreSnippet(id: snippetId)
            refreshSnippets()
            loadRecoveryItems()
            if snippets.contains(where: { $0.id == restored.id }) {
                selectSnippet(restored.id)
            }
        } catch {
            log.error("Failed to restore snippet: \(error.localizedDescription, privacy: .public)")
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

    /// Records which editor gained focus and a reference to its text view, so the
    /// Format menu command knows which editor to act on.
    func focusEditor(_ target: EditorTarget, _ textView: HighlightingTextView) {
        focusedTarget = target
        focusedTextView = textView
        register(target, textView)
    }

    /// Records an editor's backing text view by target, so per-editor toolbar
    /// commands (Format, Find) can act on a specific editor regardless of focus.
    func register(_ target: EditorTarget, _ textView: HighlightingTextView) {
        switch target {
        case .main: mainTextView = textView
        case .split: splitTextView = textView
        }
    }

    /// Moves keyboard focus to the main editor's text view. Deferred to the next
    /// main-actor turn so it lands after SwiftUI has processed the state change
    /// that triggered it (create/switch); otherwise SwiftUI can reclaim focus.
    private func focusMainEditor() {
        let textView = mainTextView
        Task { @MainActor in textView?.window?.makeFirstResponder(textView) }
    }

    /// The editor the Format menu command acts on. Falls back to `.main` when
    /// there is no split, regardless of any stale focus.
    private var effectiveFocusTarget: EditorTarget { hasSplit ? focusedTarget : .main }

    private func language(for target: EditorTarget) -> CodeLanguage {
        target == .main ? mainLanguage : splitLanguage
    }

    private func textView(for target: EditorTarget) -> HighlightingTextView? {
        target == .main ? mainTextView : splitTextView
    }

    /// Whether "Format Code" is available for `target`. A language is formattable
    /// only when a built-in formatter exists for it; otherwise silently disabled.
    func canFormat(_ target: EditorTarget) -> Bool {
        currentSnippet != nil && formatter.supports(language(for: target))
    }

    /// Whether the Format menu command is available (acts on the focused editor).
    var canFormat: Bool { canFormat(effectiveFocusTarget) }

    /// Whether the top-toolbar Format button should be enabled: at least one
    /// editor (main, or split when present) has a supported language.
    var canFormatAny: Bool { canFormat(.main) || (hasSplit && canFormat(.split)) }

    /// Reveals the in-editor find bar for `target` (FR-19). Scoped to that
    /// editor's text view; never searches the other editor or across snippets.
    func showFind(_ target: EditorTarget) {
        textView(for: target)?.showFindInterface()
    }

    /// Reveals the find bar for the focused editor via the `⌘F` shortcut. Targets
    /// the focused editor when a split exists, otherwise the main editor.
    func findFocusedEditor() {
        showFind(effectiveFocusTarget)
    }

    /// Formats the focused editor via the menu command (`⌃⌥F`).
    func formatFocusedEditor() {
        format(effectiveFocusTarget)
    }

    /// Formats all visible editors in one pass. Used by the top toolbar button so
    /// both main and split are formatted without the `isFormatting` guard blocking
    /// the second call.
    func formatAll() {
        guard !isFormatting, currentSnippet != nil else { return }
        isFormatting = true
        Task { [weak self, formatter] in
            defer { self?.isFormatting = false }
            guard let self else { return }
            do {
                for target in ([.main, .split] as [EditorTarget]) where target == .main || self.hasSplit {
                    let lang = self.language(for: target)
                    guard self.formatter.supports(lang) else { continue }
                    let tv = self.textView(for: target)
                    let source = tv?.string ?? (target == .main ? self.editorText : self.splitEditorText)
                    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let result = try await formatter.format(source, language: lang)
                    if let tv {
                        tv.replaceAllText(result)
                    } else if target == .main {
                        self.editorText = result
                    } else {
                        self.splitEditorText = result
                    }
                }
            } catch {
                let message = (error as? FormatterError)?.userFacingMessage ?? "Formatting failed."
                self.flashStatus(message)
            }
        }
    }

    /// Formats a specific editor (FR-7). Runs the formatter off the main actor,
    /// then replaces the content through the undo-registering path. Surfaces a
    /// transient banner on failure. Manual only — never triggered automatically.
    func format(_ target: EditorTarget) {
        guard !isFormatting, currentSnippet != nil else { return }
        let language = language(for: target)
        guard formatter.supports(language) else {
            flashStatus(FormatterError.unsupportedLanguage(language).userFacingMessage)
            return
        }
        let textView = textView(for: target)
        let source = textView?.string ?? (target == .main ? editorText : splitEditorText)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isFormatting = true
        Task { [weak self, formatter] in
            defer { self?.isFormatting = false }
            do {
                let result = try await formatter.format(source, language: language)
                guard let self else { return }
                if let textView {
                    textView.replaceAllText(result)
                } else if target == .main {
                    self.editorText = result
                } else {
                    self.splitEditorText = result
                }
            } catch {
                let message =
                    (error as? FormatterError)?.userFacingMessage ?? "Formatting failed."
                self?.flashStatus(message)
            }
        }
    }

    /// Shows a transient, non-modal status message that clears itself after a few
    /// seconds (matching the product's "non-blocking" principle). Used for
    /// formatting errors and limit hints (FR-21).
    func flashStatus(_ message: String) {
        statusTask?.cancel()
        transientStatus = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.transientStatus = nil
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
