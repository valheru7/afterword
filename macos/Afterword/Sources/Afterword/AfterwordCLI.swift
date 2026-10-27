import Foundation

/// The installed `afterword` command. The menu bar app only wraps it: recording, transcription
/// and note writing all happen in the CLI, so the app never drifts from what the terminal does.
struct AfterwordCLI {
    let executable: URL

    /// Apps opened from Finder or the Dock get a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin), not
    /// the one from your shell profile. These are where `uv tool install` and Homebrew put things,
    /// so we look there too, and hand the same list to the CLI so it can find whisper.cpp, ffmpeg
    /// and the `claude` command.
    private static let commonInstallDirectories = [
        "~/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ].map { NSString(string: $0).expandingTildeInPath }

    static var searchPath: [String] {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (inherited + commonInstallDirectories).filter { seen.insert($0).inserted }
    }

    /// Returns nil when `afterword` isn't installed anywhere we know to look.
    static func locate() -> AfterwordCLI? {
        for directory in searchPath {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("afterword")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return AfterwordCLI(executable: candidate)
            }
        }
        return nil
    }

    func makeProcess(arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Self.childEnvironment
        // No terminal, so nothing to type into; reading stdin would just get EOF.
        process.standardInput = FileHandle.nullDevice
        return process
    }

    private static var childEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        // Python buffers stdout when it isn't a terminal; we want progress lines as they happen.
        environment["PYTHONUNBUFFERED"] = "1"
        // GUI apps have no LANG, and titles and progress lines contain non-ASCII characters.
        environment["PYTHONIOENCODING"] = "utf-8"
        return environment
    }

    /// `afterword templates`, parsed. Throws if the command fails, so the caller can fall back.
    func templates() async throws -> [NoteTemplate] {
        let output = try await outputOfCommand(["templates"])
        let templates = output
            .split(separator: "\n")
            .compactMap(NoteTemplate.init(listingLine:))
        guard !templates.isEmpty else { throw CLIError.failed(message: "afterword templates listed nothing.") }
        return templates
    }

    /// `afterword config show --json`.
    func config() async throws -> AfterwordConfig {
        let output = try await outputOfCommand(["config", "show", "--json"])
        return try AfterwordConfig.decode(fromJSON: Data(output.utf8))
    }

    /// `afterword config set KEY VALUE`. The CLI checks the key and value; its message is thrown.
    /// Secrets go through stdin (`config set KEY -`) so they never appear in the process list.
    func setConfig(_ key: String, to value: String, isSecret: Bool = false) async throws {
        if isSecret {
            _ = try await outputOfCommand(["config", "set", key, "-"], input: value)
        } else {
            _ = try await outputOfCommand(["config", "set", key, value])
        }
    }

    /// `afterword config test-joplin`: whether it connected, and the CLI's message either way.
    func testJoplin() async throws -> (connected: Bool, message: String) {
        let result = try await run(["config", "test-joplin"])
        return (result.status == 0, result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs a short command and returns its stdout, or throws its error message.
    private func outputOfCommand(_ arguments: [String], input: String? = nil) async throws -> String {
        let result = try await run(arguments, input: input)
        guard result.status == 0 else { throw CLIError.failed(message: result.errorMessage) }
        return result.output
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        let errors: String

        /// The last thing the CLI said on stderr, without its "afterword: " prefix.
        var errorMessage: String {
            let lastLine = errors.split(separator: "\n").last.map(String.init) ?? ""
            let message = lastLine.hasPrefix("afterword: ") ? String(lastLine.dropFirst("afterword: ".count)) : lastLine
            return message.isEmpty ? "afterword exited with status \(status)." : message
        }
    }

    /// For short commands only: output is read after the process exits, which is fine while it
    /// fits in a pipe's buffer (64 KB). `afterword record` streams its output instead.
    private func run(_ arguments: [String], input: String? = nil) async throws -> CommandResult {
        let process = makeProcess(arguments: arguments)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe {
            process.standardInput = inputPipe
        }

        let exitStatuses = try launch(process)
        if let input, let inputPipe {
            // A setting is tiny, so this fits in the pipe's buffer and never blocks. Closing
            // the pipe is the end of input the CLI waits for.
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }
        let status = await exitStatuses.firstValue()
        return CommandResult(
            status: status,
            output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            errors: String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

enum CLIError: LocalizedError {
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

/// Starts `process` and returns a stream that delivers its exit status once, when it ends.
/// The termination handler must be set before `run()`, or a fast exit could be missed.
func launch(_ process: Process) throws -> AsyncStream<Int32> {
    let (exitStatuses, continuation) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { finished in
        continuation.yield(finished.terminationStatus)
        continuation.finish()
    }
    try process.run()
    return exitStatuses
}

extension AsyncStream<Int32> {
    /// The single exit status `launch` delivers.
    func firstValue() async -> Int32 {
        for await value in self { return value }
        return -1  // Unreachable in practice: the stream always yields before finishing.
    }
}
