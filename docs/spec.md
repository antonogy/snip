# CodeDrop - a scratchpad for Developers

## Product Specification v1.0

---

# 1. Vision

CodeDrop is a native macOS application for temporary code snippets.

It is designed for developers who need a fast place to:

* paste code
* write code
* compare snippets
* inspect JSON
* inspect SQL
* temporarily store technical information

without dealing with:

* files
* projects
* repositories
* folders
* save dialogs

The application is intentionally not an IDE.

---

# 2. Product Principles

## 2.1 Developer Scratchpad First

The application is a developer scratchpad, not an IDE.

Every feature should prioritize:

* speed
* low cognitive load
* minimal user interaction
* instant access to temporary code snippets

---

## 2.2 Fast

The primary workflow is:

Launch → Type

The user should never wait before writing.

---

## 2.3 Lightweight

Avoid:

* project management
* workspace management
* folder hierarchies
* git integration
* build systems
* terminal integration
* IDE workflows

---

## 2.4 Minimalist

Require the minimum possible number of actions.

Examples:

* no title editing
* no save dialogs
* no onboarding
* no language selection during snippet creation

---

## 2.5 Temporary-First

CodeDroppets are temporary by default.

Persistence exists only to prevent accidental data loss.

---

## 2.6 Helpful, Never Interrupting

The application may suggest actions.

The application must never interrupt the user.

Allowed:

* subtle actions
* contextual suggestions

Not allowed:

* modal dialogs
* onboarding
* setup wizards
* confirmation dialogs

---

## 2.7 Performance First

When choosing between:

* smarter
* faster

the faster solution wins.

The application should feel:

instant

not

intelligent.

---

# 3. Scope

## Included

* snippets
* syntax highlighting
* automatic language detection
* formatting
* split editor
* autosave
* recovery
* keyboard shortcuts

## Excluded

* projects
* workspaces
* folders
* files
* git
* plugins
* AI features
* search (global, cross-snippet — in-editor find within a single editor is supported, see FR-19)
* export
* import
* backups
* telemetry
* collaboration
* code execution
* debugging

---

# 4. Functional Requirements

## FR-1 CodeDroppet Lifecycle

* snippets are temporary by default
* snippets are automatically saved
* snippets are restored after restart
* snippets may be pinned
* unpinned snippets expire after inactivity period
* snippets may be manually deleted
* expired snippets may be manually cleared
* on launch, snippets whose editors are all empty are removed
* the number of active snippets is capped (see FR-21)

A snippet counts as empty only when its main editor and its split editor (if
present) are both empty.

Empty snippets are permanently discarded on launch, not moved to Recovery —
there is nothing to recover.

Default expiration:

* 7 days after last modification

---

## FR-2 Smart Titles

Snippets have no separate generated title. The sidebar card shows a live preview
of the snippet's content instead:

* the first up to 3 non-empty lines of the main editor
* equal-weight monospace
* an empty snippet shows a dim "Empty" placeholder

The language is shown separately on the card, so the preview need not repeat it.

A single-line label (the first content line) is retained internally for the
Recovery list. Manual title editing is not supported.

The preview is derived from a small head of the content file, never a full read,
so it has no noticeable performance impact.

---

## FR-3 Language Detection

Supported languages:

* JavaScript
* TypeScript
* JSON
* HTML
* CSS
* SQL
* Swift
* Python
* Bash
* Markdown
* YAML
* PHP
* GraphQL
* Flow
* Vue
* Angular
* Plain Text

Auto-detected: JavaScript, TypeScript, JSON, HTML, CSS, SQL, Swift, Python,
Bash, Markdown, YAML, PHP, GraphQL. Flow, Vue, and Angular are selected
manually only — they are JS-like or template dialects with no reliable
auto-detection signature.

Syntax highlighting covers every language above except GraphQL and Vue, which
are format-only (no tree-sitter grammar ships for them); their text stays
uncolored but Format Code still works. Flow reuses the JavaScript grammar.
Markdown, HTML, and Angular additionally highlight embedded languages (fenced
code blocks, `<script>`/`<style>`) via tree-sitter injection.

Detection runs:

* on creation
* after paste
* after content changes

Manual override disables auto detection.

If editor becomes empty:

* auto detection is re-enabled
* manual override is cleared

---

## FR-4 Split Editor

Each snippet may contain:

* main editor
* optional split editor

Rules:

* one split only
* vertical or horizontal
* split content is empty on creation
* split content is independent
* split language is independent
* split starts as Plain Text with auto-detection enabled
* split language is detected independently from the split's own content

Auto title is always generated from main editor.

---

## FR-5 CodeDroppet Navigation

Navigation uses compact sidebar cards.

Card contains:

* title
* language
* pin state
* keyboard shortcut hint (⌘1–⌘9 for the first 9 snippets)
* split indicator

Ordering:

1. pinned snippets
2. unpinned snippets

Within group:

* newest first

---

## FR-6 Command Palette

Deferred to the Future Exploration Backlog (see §10).

The command set is small enough today that a dedicated palette is
overabundant; commands are reached via menus and keyboard shortcuts instead.

---

## FR-7 Formatting

Formatting is manual only.

All formatters are built in and run in-process — no external CLI tools or
user setup are required.

Supported:

* JavaScript → Prettier (bundled, in-process)
* TypeScript → Prettier (bundled, in-process)
* JSON → Prettier (bundled, in-process)
* HTML → Prettier (bundled, in-process)
* CSS → Prettier (bundled, in-process)
* Markdown → Prettier (bundled, in-process)
* YAML → Prettier (bundled, in-process)
* PHP → Prettier (bundled, in-process)
* GraphQL → Prettier (bundled, in-process)
* Flow → Prettier (bundled, in-process)
* Vue → Prettier (bundled, in-process)
* Angular → Prettier (bundled, in-process)
* Swift → swift-format (bundled, in-process)

Not formattable (no built-in formatter):

* SQL
* Python
* Bash
* Plain Text

Availability:

* if a built-in formatter exists for the editor's language, "Format Code" is
  enabled
* if no formatter exists, the feature is silently disabled — "Format Code" is
  disabled, with no error or install prompt
* Plain Text is always disabled

Formatting never runs automatically.

---

## FR-8 Keyboard First

Supported shortcuts:

* ⌘N New CodeDroppet
* ⌘B Toggle Sidebar
* ⌘⌫ Delete CodeDroppet
* ⌘1-⌘9 Switch CodeDroppet

Additional shortcuts TBD.

---

## FR-9 Autosave & Recovery

* autosave is automatic
* no save action exists
* no save dialogs exist
* state is restored after restart
* state is restored after crash

---

## FR-10 Editor

Supported:

* typing
* copy
* paste
* cut
* undo
* redo
* line numbers
* syntax highlighting
* word wrap
* current line highlight
* in-editor find (scoped to a single editor — see FR-19)
* cursor position indicator (see FR-19)

Not supported:

* minimap
* folding
* multiple cursors

---

## FR-11 Deletion & Expiration

Deleted and expired snippets move to Recovery.

Recovery retention:

* 30 days

After retention:

* permanent deletion

No confirmation dialogs.

---

## FR-12 Visual Design

Requirements:

* native macOS controls
* dark mode
* light mode
* compact layout

No onboarding.

No tutorials.

No feature tours.

---

## FR-13 Storage

Local-first.

No login.

No account.

No internet required.

Future support:

* iCloud Sync only

No export.

No import.

No backups.

---

## FR-14 Language Switching UX

Language displayed in toolbar.

Manual selection disables auto detection.

Auto Detect may be restored manually.

Empty editor automatically returns to Auto Detect mode.

---

## FR-15 New CodeDroppet Creation

Creating a snippet:

* creates empty snippet
* enables Auto Detect
* focuses editor
* requires no further interaction

---

## FR-16 Startup Performance

Startup sequence:

Open App → Restore → Type

Startup should not block on:

* cleanup
* sync
* detection
* background tasks

The launch-time empty-snippet purge (FR-1) is metadata-only — no content reads —
and runs as part of restore without delaying first paint.

---

## FR-17 CodeDroppet Switching Performance

Switching snippets should feel like switching browser tabs.

No loading indicators.

No progress indicators.

---

## FR-18 No Onboarding

First launch:

Open App → Empty CodeDroppet → Type

No onboarding flow.

---

## FR-19 Editor Toolbar

Each editor — main and split — has its own toolbar.

The toolbar provides:

* **In-editor search** — find text within that editor's content only
* **Format Code** — accessed via the top toolbar (FR-20); formats all open
  editors at once; availability is gated per FR-7
* **Language switcher** — shows the current language and allows manual
  selection; manual selection disables auto detection per FR-14

Each editor also has a **bottom status bar** showing the current cursor position
(`Line: <n>  Col: <n>`), right-aligned. It updates live on every cursor move or
selection change and is independent per editor in a split.

Scope:

* each editor in a split keeps independent toolbar state — its own language and
  its own search session
* in-editor search is scoped to a single editor; it is not global, cross-snippet
  search (see §3 Excluded)

In-editor search:

* matches within the active editor only
* highlights matches and supports next/previous navigation
* clears when dismissed
* never searches across snippets or the other editor in a split

---

## FR-20 Top Toolbar

The application's top toolbar (principal/centre slot and right action slot).

**Centre (principal slot):**

* **Pin / Unpin** — toggles the pin state of the selected snippet (FR-1, FR-5)
* **Format Code** — formats all open editors; gated per FR-7 (enabled only when
  at least one editor has a built-in formatter; silently disabled otherwise)
* **Delete** — soft-deletes the selected snippet into Recovery (FR-11); same
  action as ⌘⌫

**Right (primary action slot):**

* When no split is active: **Split Right** and **Split Down** buttons
* When a split is active: one orientation-switch button (Split Down when
  vertical, Split Right when horizontal) and a **Close Split** button

**Sidebar bottom-left:**

* **New CodeDroppet** — creates a snippet per FR-15; respects the snippet limit
  (FR-21)

State:

* snippet-scoped buttons (Pin/Unpin, Format Code, Delete, Split) are disabled
  when no snippet is selected
* Format Code is also disabled when no open editor's language has a built-in
  formatter

---

## FR-21 Limits

### CodeDroppet Count

* maximum 100 active snippets
* "active" excludes deleted and expired snippets held in Recovery (FR-11)
* when the cap is reached, New CodeDroppet (FR-15, FR-20, ⌘N) is disabled with a
  subtle, non-modal hint — no dialog, no interruption (§2.6)
* deleting, expiring, or clearing snippets frees capacity

### Paste Size

* large pastes must never crash or freeze the application (see §5
  Responsiveness)
* the maximum safe paste / content size is an open investigation (see §10);
  until a concrete limit is set, oversized input must be guarded so the editor
  degrades gracefully rather than hanging
* the guard applies to paste, drag-in, and programmatic content loads

---

# 5. Non-Functional Requirements

## Responsiveness

Typing:

<16 ms target

CodeDroppet switch:

<100 ms target

Command palette:

<50 ms target

---

## Resource Usage

Target memory:

<150 MB

Idle CPU:

approximately 0%

---

## Reliability

User content should never be lost.

Crash recovery required.

---

## Native macOS Experience

Native only.

Required:

* Swift
* SwiftUI
* AppKit
* TextKit
* Tree-sitter

Supported CPUs:

* Apple Silicon
* Intel

---

# 6. Data Model

## CodeDroppet

```swift
struct CodeDroppet {
    let id: UUID

    var title: String
    var titleSource: CodeDroppetTitleSource

    var mainEditor: EditorDocument
    var splitEditor: EditorDocument?

    var splitOrientation: SplitOrientation?

    var isPinned: Bool

    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    var expiresAt: Date?
    var deletedAt: Date?
}
```

## EditorDocument

```swift
struct EditorDocument {
    let id: UUID

    var contentFilePath: String

    var language: CodeLanguage
    var languageMode: LanguageMode

    var cursorPosition: Int?
    var selectedRange: TextRange?
    var scrollOffset: Double?

    var createdAt: Date
    var updatedAt: Date
}
```

## AppState

```swift
struct AppState {
    var selectedCodeDroppetId: UUID?

    var sidebarVisible: Bool
    var sidebarWidth: Double

    var windowFrame: WindowFrame?

    var commandPaletteRecentCommands: [CommandId]
}
```

## Settings

```swift
struct Settings {
    var expirationDays: Int
    var deletionGracePeriodDays: Int

    var appearanceMode: AppearanceMode
    var wordWrapEnabled: Bool

    var iCloudSyncEnabled: Bool
}
```

---

# 7. Storage Architecture

```text
App Sandbox Container
├─ metadata.sqlite
├─ app_state.json
├─ settings.json
└─ contents/
   └─ editor_<uuid>.txt
```

SQLite:

* snippets
* editor_documents
* recovery_items
* schema_migrations

Content stored as separate files.

---

# 8. Application Architecture

```text
App
├─ UI
├─ CodeDroppets
├─ Editor
├─ Language
├─ Formatting
├─ Recovery
├─ CommandPalette
├─ Storage
└─ Sync (future)
```

Dependency rule:

UI
↓
Domain Modules
↓
Storage

Never:

UI
↓
SQLite

---

# 9. Architectural Constraints

## Native macOS Only

Supported:

* macOS Sequoia+
* Apple Silicon
* Intel

Not supported:

* Windows
* Linux
* Web
* iOS
* Android

---

## Single Window

Only one application window.

---

## No Plugin System

Not supported.

---

## No Telemetry

No analytics collection.

No snippet inspection.

---

## No Background Daemons

No launch agents.

No menu bar helpers.

No login items.

---

# 10. Future Exploration Backlog

## Contextual Subtle Actions

Examples:

* Format JSON
* Format SQL
* Pretty Print Minified Code
* Choose Language
* Pin CodeDroppet Suggestion

Must remain:

* optional
* contextual
* non-blocking
* non-modal

---

## Command Palette

Deferred from FR-6.

Reason:

* the current command set is small; a dedicated palette is overabundant for now
* commands remain reachable via menus and keyboard shortcuts

Shortcut (when implemented):

⌘⇧P

Proposed commands:

### CodeDroppets

* New CodeDroppet
* Delete CodeDroppet
* Pin CodeDroppet
* Unpin CodeDroppet
* Clear Expired CodeDroppets

### Editor

* Format Code
* Detect Language
* Change Language
* Focus Main Editor
* Focus Split Editor

### Split

* Split Right
* Split Down
* Close Split

### Application

* Open Settings
* Toggle Sidebar

Command list will be reviewed after prototype validation.

---

## Formatting Enhancements

Extend formatting beyond the current built-in, in-process formatters (FR-7):

* implement formatters for SQL, Python, and Bash
* native implementation of the Prettier formatter
* add syntax highlighting for GraphQL and Vue (no tree-sitter grammar ships for
  them yet; they are currently format-only)

---

## Maximum Content Size

Determine the maximum safe paste / editor content size before performance
degrades (referenced by FR-21).

Goals:

* find the threshold at which highlighting, layout, or autosave begin to stall
* define a concrete limit and a graceful-degradation strategy (e.g. disable
  highlighting, truncate, or warn non-modally) for content beyond it

Must never crash or freeze the application.

---

## iCloud Sync

Only future cloud feature currently approved.
