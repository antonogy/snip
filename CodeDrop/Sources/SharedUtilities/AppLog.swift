import Foundation
import os

/// Central factory for `os.Logger` instances so every module shares one subsystem.
public enum AppLog {
    /// Unified-logging subsystem for the whole app.
    public static let subsystem = "com.snip.app"

    /// Returns a logger for the given category (e.g. "storage", "app").
    public static func make(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
