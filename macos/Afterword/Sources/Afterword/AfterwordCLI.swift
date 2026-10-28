import Foundation

/// The `afterword` command. The menu bar app only wraps it: recording, transcription and note
/// writing all happen in the CLI, so the app never drifts from what the terminal does.
///
/// A release build of the app carries its own copy (Python, whisper.cpp, ffmpeg and the capture
/// helper; see bundle-tools.sh). Without one, it uses the `afterword` installed on this Mac.
struct AfterwordCLI {
    let executable: URL
    /// Arguments that come before the command, e.g. `-m afterword.cli` for the bundled Python.
    let leadingArguments: [String]
    /// The bundle's Contents/Helpers folder with whisper-cli, ffmpeg and afterword-capture, or
    /// nil when using an installed CLI.
    let bundledTools: URL?

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

    /// The bundled copy if this app has one, otherwise an installed `afterword`. Returns nil
    /// when there's neither.
    static func locate() -> AfterwordCLI? {
        bundled() ?? installed()
    }

    private static func bundled() -> AfterwordCLI? {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let python = contents.appendingPathComponent("Resources/python/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return nil }
        return AfterwordCLI(
            executable: python,
            // -I: ignore the user's PYTHON* variables and site-packages, so nothing outside the
            // bundle changes how it runs. -B: never write .pyc files into the (signed) bundle;
            // they're compiled at build time. -u and -X utf8: unbuffered UTF-8 output, since
            // -I also ignores PYTHONUNBUFFERED and PYTHONIOENCODING.
            leadingArguments: ["-I", "-B", "-u", "-X", "utf8", "-m", "afterword.cli"],
            bundledTools: contents.appendingPathComponent("Helpers")
        )
    }

    private static func installed() -> AfterwordCLI? {
        for directory in searchPath {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("afterword")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return AfterwordCLI(executable: candidate, leadingArguments: [], bundledTools: nil)
            }
        }
        return nil
    }

    func makeProcess(arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = leadingArguments + arguments
        process.environment = childEnvironment
        // No terminal, so nothing to type into; reading stdin would just get EOF.
        process.standardInput = FileHandle.nullDevice
        return process
    }

    private var childEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var path = Self.searchPath
        if let bundledTools {
            // The bundle's whisper-cli and ffmpeg come first, so a Homebrew copy can't replace
            // them; the rest of PATH still finds `claude` for the Claude Code notes writer.
            path.insert(bundledTools.path, at: 0)
            environment["AFTERWORD_CAPTURE_BIN"] = bundledTools.appendingPathComponent("afterword-capture").path
        }
        environment["PATH"] = path.joined(separator: ":")
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

    /// `afterword download-model --check`: whether the Whisper model is already on this Mac.
    func isModelDownloaded() async -> Bool {
        let result = try? await run(["download-model", "--check"])
        return result?.status == 0
    }

    /// `afterword download-model`, passing each progress line to `progress` as it arrives.
    func downloadModel(progress: (String) -> Void) async throws {
        let process = makeProcess(arguments: ["download-model"])
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let exitStatuses = try launch(process)
        // Read stderr while it runs, not after: if it filled the pipe's buffer before exiting,
        // the CLI would block on writing and never exit.
        let errorTail = Task {
            var lines: [String] = []
            for await line in errors.fileHandleForReading.lines() {
                lines.append(line)
                if lines.count > 12 { lines.removeFirst() }  // The end is where the error is.
            }
            return lines
        }
        for await line in output.fileHandleForReading.lines() where !line.isEmpty {
            progress(line)
        }
        let status = await exitStatuses.firstValue()
        let errorLines = await errorTail.value
        guard status == 0 else {
            let errorText = errorLines.joined(separator: "\n")
            throw CLIError.failed(message: CommandResult(status: status, output: "", errors: errorText).errorMessage)
        }
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
