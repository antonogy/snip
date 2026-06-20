# CodeDrop - a scratchpad for Developers

# Implementation Plan v1.0

---

# 1. Goals

Build a production-quality native macOS application that satisfies the approved Product Specification.

Primary goals:

* native macOS experience
* instant startup
* instant editing
* zero-friction persistence
* temporary-first workflow
* minimal maintenance complexity

The implementation should prioritize:

1. correctness
2. responsiveness
3. simplicity

over feature richness.

---

# 2. Technology Stack

## Platform

* macOS Sequoia+
* Apple Silicon
* Intel

## Language

* Swift 6+

## UI

* SwiftUI

## Editor

* AppKit bridge
* TextKit 2 where practical

## Syntax Highlighting

* Tree-sitter

## Persistence

* SQLite
* JSON
* local content files

## Database Layer

Recommended:

* GRDB

Reason:

* lightweight
* mature
* excellent Swift integration
* migration support
* no unnecessary abstraction

## Logging

* os.Logger

## Dependency Management

* Swift Package Manager

---

# 3. High-Level Architecture

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
└─ Sync (Future)
```

Dependency flow:

```text
UI
 ↓
Feature Modules
 ↓
Storage
```

Forbidden:

```text
UI
 ↓
SQLite
```

---

# 4. Repository Structure

```text
CodeDrop/
├─ CodeDropApp/
│
├─ Packages/
│   ├─ CodeDroppets/
│   ├─ Editor/
│   ├─ Language/
│   ├─ Formatting/
│   ├─ Recovery/
│   ├─ CommandPalette/
│   ├─ Storage/
│   ├─ SharedModels/
│   └─ SharedUtilities/
│
├─ Resources/
│   ├─ TreeSitter/
│   └─ Localization/
│
├─ Tests/
│   ├─ Unit/
│   ├─ Integration/
│   └─ Performance/
│
└─ Scripts/
```

---

# 5. External Dependencies

## Required

### GRDB

Purpose:

* SQLite access
* migrations

### Tree-sitter

Purpose:

* syntax highlighting
* language parsing

### Tree-sitter grammars

Initial languages:

* JavaScript
* TypeScript
* JSON
* HTML
* CSS
* SQL
* Swift
* Python
* Bash

---

# 6. Milestones

---

# Milestone 1 — Foundation

Estimated Outcome:

Application launches and restores state.

## Features

* app lifecycle
* single window
* storage initialization
* app state persistence
* settings persistence
* logging

## Deliverables

* project structure
* SQLite initialization
* migrations
* JSON configuration loading
* startup restoration (triggers the empty-snippet purge — see Milestone 10)

## Exit Criteria

Application launches successfully.

State restoration works.

---

# Milestone 2 — Editor Core

Estimated Outcome:

Single editable snippet.

## Features

* editor component
* line numbers
* word wrap
* current line highlight
* undo/redo

## Deliverables

* TextKit integration
* editor abstraction

## Exit Criteria

User can type, edit, copy, paste.

---

# Milestone 3 — Autosave & Recovery

Estimated Outcome:

Data persistence works.

## Features

* autosave
* restore after restart
* restore after crash

## Deliverables

* debounced save pipeline
* content file storage
* recovery validation

## Exit Criteria

No data loss during normal usage.

---

# Milestone 4 — CodeDroppets

Estimated Outcome:

Multiple snippets supported.

## Features

* create snippet
* delete snippet
* pin snippet
* sidebar cards
* snippet ordering

## Deliverables

* snippet repository
* snippet list UI

## Exit Criteria

Multiple snippets work correctly.

---

# Milestone 5 — Split Editor

Estimated Outcome:

Comparison workflow supported.

## Features

* horizontal split
* vertical split
* independent content
* independent language state

## Deliverables

* split layout UI
* split persistence

## Exit Criteria

Split state survives restart.

---

# Milestone 6 — Language Detection

Estimated Outcome:

Automatic language detection.

## Features

* detection engine
* auto/manual mode
* language switching

## Deliverables

* language service
* language toolbar UI

## Exit Criteria

Detection works reliably.

---

# Milestone 7 — Syntax Highlighting

Estimated Outcome:

Highlighted code.

## Features

* Tree-sitter integration
* highlighting pipeline

## Deliverables

* language grammars
* highlighter engine

## Exit Criteria

All supported languages highlight correctly.

---

# Milestone 8 — Formatting

Estimated Outcome:

Manual formatting.

## Features

* format command
* in-process formatter execution (Prettier + swift-format; no external CLIs)
* availability gating (enabled only when a built-in formatter exists for the
  language; silently disabled otherwise, Plain Text always disabled)
* formatter errors

## Deliverables

* formatter abstraction

## Exit Criteria

Languages with a built-in formatter format correctly; languages without one
have the command disabled.

---

# Milestone 9 — Command Palette (Deferred)

Deferred to Future Work (see §12).

The current command set is small enough that a dedicated palette is
overabundant; commands are reached via menus and keyboard shortcuts instead.
Revisit after prototype validation.

---

# Milestone 10 — Deletion & Recovery

Estimated Outcome:

Lifecycle management complete.

## Features

* expiration
* recovery
* restore
* cleanup
* empty-snippet purge on launch (permanent, bypasses Recovery)

## Deliverables

* recovery UI
* cleanup jobs

## Exit Criteria

Recovery workflow functions correctly.

---

# Milestone 11 — Toolbars & Limits

Estimated Outcome:

Per-editor and top-level toolbars, plus safety limits.

## Features

* per-editor toolbar (FR-19): in-editor search, language switcher (FR-14);
  Format Code is in the top toolbar, not per-editor
* top toolbar (FR-20):
  * centre slot — Pin/Unpin, Format Code (formats all editors, gated per FR-7),
    Delete
  * right slot — Split Right / Split Down (or Close Split when split active)
  * sidebar bottom-left — New CodeDroppet button
* snippet limit — max 100 active snippets, excluding Recovery (FR-21)
* paste-size guard — prevent crashes/freezes on oversized input (FR-21)

## Deliverables

* editor toolbar component, with independent state per editor / split
* in-editor find (NSTextFinder / TextKit-backed), scoped to a single editor
* top toolbar wiring to pin, format-all, delete, and split commands
* sidebar New CodeDroppet button with cap enforcement and non-modal hint at limit
* content-size guard plus investigation of the maximum safe paste size

## Exit Criteria

Toolbars function correctly.

The snippet limit is enforced without modal interruption.

Large pastes never crash or freeze the app.

---

# Milestone 12 — UX Polish

Estimated Outcome:

Production-ready user experience.

## Features

* keyboard navigation
* animations
* visual polish
* empty states

## Exit Criteria

Application feels native and responsive.

---

# Milestone 13 — Performance Pass

Estimated Outcome:

Performance targets validated.

## Areas

* startup
* typing
* snippet switching
* autosave

## Deliverables

* performance benchmarks
* profiling results

## Exit Criteria

Performance targets achieved.

---

# 7. Storage Implementation

## SQLite

Tables:

* snippets
* editor_documents
* recovery_items
* schema_migrations

## JSON

Files:

```text
app_state.json
settings.json
```

## Content Files

```text
contents/editor_<uuid>.txt
```

Content stored separately from metadata.

---

# 8. Autosave Strategy

## Save Trigger

```text
Editor Change
↓
1 second debounce
↓
Atomic file write
↓
Metadata update
```

## Requirements

* no blocking UI
* no data loss
* no manual save

---

# 9. Testing Strategy

## Unit Tests

Coverage:

* language detection
* expiration rules
* recovery rules
* title generation
* command execution

---

## Integration Tests

Coverage:

* storage
* autosave
* restore
* migration handling

---

## Performance Tests

Coverage:

* startup time
* typing latency
* snippet switching

---

## Manual Validation

Scenarios:

* force quit
* power loss simulation
* hundreds of snippets
* large JSON payloads
* large SQL queries

---

# 10. Performance Targets

## Startup

Target:

< 500 ms perceived startup

Stretch Goal:

< 250 ms

---

## Typing

Target:

< 16 ms response

---

## CodeDroppet Switching

Target:

< 100 ms

---

## Command Palette

Target:

< 50 ms

---

# 11. Risks

## Tree-sitter Integration

Risk:

* syntax highlighting complexity

Mitigation:

* isolate behind dedicated module

---

## Editor Performance

Risk:

* large content handling

Mitigation:

* lazy rendering
* profiling

---

## Feature Creep

Risk:

Application becoming a mini IDE.

Mitigation:

Enforce Product Principles.

---

# 12. Future Work (Not MVP)

## Approved Future Items

* iCloud Sync
* Contextual Subtle Actions
* Command Palette (deferred from Milestone 9 — small command set makes it
  overabundant for now; reachable via menus and shortcuts)
* Formatting enhancements:
  * formatters for SQL, Python, and Bash
  * native implementation of the Prettier formatter
  * formatting support for YAML, GraphQL, Markdown, and Flow

## Explicitly Rejected

* projects
* git integration
* plugins
* AI
* search
* export
* import
* backup
* code execution
* debugging
* LSP
* autocomplete
* telemetry

---

# Definition of Done

The application is considered MVP complete when:

* all functional requirements are implemented
* all non-functional requirements are satisfied
* startup feels instant
* editing feels instant
* autosave is reliable
* recovery is reliable
* split editor works
* syntax highlighting works
* formatting works
* application remains faithful to the Developer CodeDrop First philosophy
