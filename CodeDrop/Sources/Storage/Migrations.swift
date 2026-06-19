import Foundation
import GRDB

/// Schema definition for the metadata database.
///
/// GRDB tracks which migrations have run in its own `grdb_migrations` table, so
/// migrations are append-only: never edit a registered migration once shipped —
/// add a new one.
enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            // Editor documents. Text content lives in files, not here.
            try db.create(table: "editor_documents") { t in
                t.primaryKey("id", .text)
                t.column("content_file_path", .text).notNull()
                t.column("language", .text).notNull()
                t.column("language_mode", .text).notNull()
                t.column("cursor_position", .integer)
                t.column("selected_range_location", .integer)
                t.column("selected_range_length", .integer)
                t.column("scroll_offset", .double)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Snippets reference their editor documents.
            try db.create(table: "snippets") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("title_source", .text).notNull()
                t.column("main_editor_id", .text)
                    .notNull()
                    .references("editor_documents", onDelete: .restrict)
                t.column("split_editor_id", .text)
                    .references("editor_documents", onDelete: .setNull)
                t.column("split_orientation", .text)
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("last_opened_at", .datetime)
                t.column("expires_at", .datetime)
                t.column("deleted_at", .datetime)
            }
            // Ordering and expiry sweeps query these columns.
            try db.create(
                index: "idx_snippets_pinned_updated",
                on: "snippets",
                columns: ["is_pinned", "updated_at"]
            )
            try db.create(index: "idx_snippets_expires_at", on: "snippets", columns: ["expires_at"])

            // Soft-deleted / expired snippets awaiting purge.
            try db.create(table: "recovery_items") { t in
                t.primaryKey("id", .text)
                t.column("snippet_id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("deleted_at", .datetime).notNull()
                t.column("purge_after", .datetime).notNull()
            }
            try db.create(
                index: "idx_recovery_items_purge_after",
                on: "recovery_items",
                columns: ["purge_after"]
            )
        }

        return migrator
    }

    /// Table names created by `v1`, used for verification.
    static let expectedTables = ["editor_documents", "snippets", "recovery_items"]
}
