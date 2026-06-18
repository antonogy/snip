import Foundation
import SharedModels

/// Runs the external CLI formatters (everything except Swift) by piping the
/// document through the tool's stdin and reading its formatted stdout.
///
/// All work is synchronous and blocking; ``CodeFormatter`` calls it from a GCD
/// global queue (via ``runAsync(spec:input:language:)``) so it never blocks the
/// main actor or the Swift concurrency cooperative pool.
enum ProcessFormatter {
    /// The executable + arguments used to format a given language. The tools all
    /// read from stdin and write formatted output to stdout.
    struct CommandSpec: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    /// Maps a language to its CLI formatter invocation, or `nil` when the language
    /// is not handled here. Swift formats in-process via `swift-format`; the
    /// Prettier languages (JS/TS/JSON/CSS/HTML) format in-process via the bundled
    /// Prettier engine; Plain Text has no formatter.
    static func commandSpec(for language: CodeLanguage) -> CommandSpec? {
        switch language {
        case .sql: return CommandSpec(executable: "sql-formatter", arguments: [])
        case .python: return CommandSpec(executable: "black", arguments: ["-q", "-"])
        case .bash: return CommandSpec(executable: "shfmt", arguments: [])
        case .javascript, .typescript, .json, .html, .css, .swift, .plainText: return nil
        }
    }

    /// Async wrapper: dispatches the blocking run onto a global queue so the
    /// caller's executor (often the main actor) stays free.
    static func runAsync(
        spec: CommandSpec,
        input: String,
        language: CodeLanguage
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try run(spec: spec, input: input, language: language))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Blocking execution. Resolves the tool on `PATH`, pipes `input` through it,
    /// and returns stdout, mapping every failure mode to a ``FormatterError``.
    static func run(
        spec: CommandSpec,
        input: String,
        language: CodeLanguage,
        timeout: TimeInterval = 15
    ) throws -> String {
        // Blank input formats to itself — don't spawn a process for nothing.
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return input
        }

        guard let executableURL = resolveExecutable(spec.executable) else {
            throw FormatterError.toolNotFound(tool: spec.executable, language: language)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = spec.arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = augmentedPath()
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw FormatterError.executionFailed(tool: spec.executable, message: error.localizedDescription)
        }

        // Drain stdout/stderr on background threads while we feed stdin, so a
        // large document can't deadlock against a child that is simultaneously
        // filling its stdout pipe (both pipes blocking on a full buffer).
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()
        for (pipe, box) in [(stdoutPipe, stdoutBox), (stderrPipe, stderrBox)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }

        let inputData = Data(input.utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            stdinPipe.fileHandleForWriting.write(inputData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        // Wall-clock timeout: terminate the tool if it overruns.
        let didTimeOut = Flag()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                didTimeOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()
        group.wait()

        if didTimeOut.isSet {
            throw FormatterError.timedOut(tool: spec.executable)
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: stderrBox.value, as: UTF8.self)
            throw FormatterError.executionFailed(tool: spec.executable, message: stderr)
        }

        return String(decoding: stdoutBox.value, as: UTF8.self)
    }

    // MARK: - PATH resolution

    /// Directories prepended to the inherited `PATH`. A GUI app launched from
    /// Finder/`open` inherits only a minimal `PATH` (`/usr/bin:/bin:…`) that
    /// excludes Homebrew, npm-global, and pipx/`--user` installs, so we add the
    /// common locations where these formatters land.
    private static var extraSearchDirectories: [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
        ]
    }

    /// The `PATH` value handed to the child process: extra directories first,
    /// then whatever the app inherited, de-duplicated and order-preserving.
    static func augmentedPath() -> String {
        let inherited = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        return (extraSearchDirectories + inherited)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }

    /// Locates `executable` by scanning the augmented search path for an existing
    /// executable file. Returns `nil` when the tool isn't installed.
    private static func resolveExecutable(_ executable: String) -> URL? {
        let manager = FileManager.default
        for dir in augmentedPath().split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(executable)
            if manager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// Thread-safe accumulator for pipe data read off a background queue.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ newValue: Data) {
        lock.lock()
        data = newValue
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Thread-safe one-way boolean flag (set once from the watchdog, read after join).
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
