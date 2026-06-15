# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build the app
cd Snip && swift build

# Run the app (opens the macOS window)
cd Snip && swift run Snip

# Headless startup verification (exercises full launch/restore path without opening a window)
cd Snip && swift run Snip --self-check

# Run all tests
cd Snip && swift test

# Run a single test by name
cd Snip && swift test --filter migrationsCreateExpectedSchema

# Format code (uses .swift-format config: 4-space indent, 110 char line length)
cd Snip && swift-format format --in-place --recursive Sources/ Tests/
```

The Xcode project (`Snip.xcodeproj`) is the preferred way to build for distribution; `swift build` is fine for development and CI.

## Architecture

### Module Dependency Graph

```
SnipApp (executable)
  └── Storage
        └── SharedModels
        └── SharedUtilities
        └── GRDB (external, SQLite)
  └── SharedModels
  └── SharedUtilities
```

`SharedModels` has **zero dependencies** and is the only module every other module may import freely. `Storage` must never be imported directly by SwiftUI views — all persistence flows through `AppModel`.

### Key Types

| Type | Module | Role |
|------|--------|------|
| `AppModel` | SnipApp | `@Observable` root owned by `SnipApp`; single source of truth for settings, app state, and storage health. Injected into the view hierarchy via `.environment(model)`. |
| `StorageStack` | Storage | Composition root for persistence. Owns the GRDB `DatabaseQueue`, `ContentStore`, and `JSONConfigStore`. Built once at launch; `Sendable`. |
| `AppDirectories` | SharedUtilities | Resolves all on-disk paths. Inject a temp directory in tests; production resolves `~/Library/Application Support/Snip/`. |
| `ContentStore` | Storage | Manages flat `.txt` files under `contents/`. Metadata rows store only relative filenames (`editor_<uuid>.txt`); this type makes them absolute. |
| `Migrations` | Storage | Append-only GRDB migrations. **Never edit a registered migration** — add a new one. |
| `SelfCheck` | SnipApp | Headless smoke-test invoked via `--self-check`. Exercises the full storage init path without opening a window. |

### Storage Layout

```
~/Library/Application Support/Snip/
├── metadata.sqlite       ← GRDB: snippets, editor_documents, recovery_items
├── app_state.json        ← sidebar visibility, window frame, selected snippet
├── settings.json         ← appearance, expiration days, word wrap
└── contents/
    └── editor_<uuid>.txt ← one file per EditorDocument
```

SQLite holds all metadata; editor text lives in separate files to keep the database small and writes atomic.

### Startup / Restoration Flow

`Entrypoint.main()` → intercepts `--self-check` early → else `SnipApp.main()` → `AppModel.init()` → `StorageStack.init()` (DB open + migrations) → `stack.restore()` (loads `app_state.json` + `settings.json`). If `StorageStack` throws, `AppModel` surfaces `initializationError` and runs with defaults rather than crashing — reliability over correctness on launch.

### Autosave Pattern

Window geometry changes debounce 500 ms via a cancellable `Task`, then flush to `app_state.json`. On `NSApplication.willTerminateNotification`, the pending task is cancelled and state is flushed immediately. The same debounce pattern will apply to editor content saves (1 s debounce → atomic file write → metadata update).

## Project Constraints

- **macOS 15+ only** (Sequoia). Swift 6 strict concurrency is enabled (`swiftLanguageModes: [.v6]`).
- **Single window** — `Window("Snip", id: "main")`. Never add a second scene or window.
- **No telemetry, no plugins, no onboarding, no IDE features** — enforced in `.claude/rules/project.md`.
- **No direct SQLite from UI** — views read only from `AppModel`; only `Storage` module touches GRDB.
- **Business logic stays out of views** — SwiftUI files contain layout and bindings only.

## Testing

Tests use Swift Testing (`@Test`, `#expect`). Each test creates its own `AppDirectories` under a UUID-named temp directory and cleans up with `defer`. The `StorageStack` is the primary integration test surface — no mocks for the database layer.
