import AppKit
import Observation

/// Runs `afterword record` and follows it from start to finished note.
@Observable
final class Recorder {
    enum Phase: Equatable {
        case idle
        /// The CLI is starting the capture helper. The first time, macOS shows its microphone and
        /// system audio permission prompts here.
        case starting
        case recording(since: Date)
        /// Stopped; the CLI is transcribing and writing the note. `progress` is its latest line.
        case writingNotes(progress: String)
        case finished(note: URL?)
        case failed(details: String)

        var isBusy: Bool {
            switch self {
            case .starting, .recording, .writingNotes: true
            case .idle, .finished, .failed: false
            }
        }

        /// The microphone may be live: there's something for Stop to stop.
        var isCapturing: Bool {
            switch self {
            case .starting, .recording: true
            case .idle, .writingNotes, .finished, .failed: false
            }
        }

        var isWritingNotes: Bool {
            if case .writingNotes = self { true } else { false }
        }
    }

    /// Why a stop was requested. Cancelling before the recorder started isn't a failure.
    private enum StopRequest {
        case cancelBeforeRecording
        case stop
    }

    /// One `afterword record` process and what it has told us so far. Each run gets its own
    /// object, so pipe readers that outlive their run (see `finish`) can't touch the next one.
    private final class Run {
        let process: Process
        let title: String
        var stopRequest: StopRequest?
        var sessionDirectory: String?
        var savedNote: URL?
        var errorLines: [String] = []
        var openPipes = 2

        init(process: Process, title: String) {
            self.process = process
            self.title = title
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var cli: AfterwordCLI?
    /// From `afterword config show --json`; the defaults until it answers.
    private(set) var config = AfterwordConfig.defaults
    private(set) var templates: [NoteTemplate] = NoteTemplate.builtIn
    private(set) var recentNotes: [RecentNote] = []

    private var run: Run?
    private var isQuitting = false
    /// The most recent notification being handed to the system, so quitting can wait for it.
    private var lastNotification: Task<Void, Never>?

    init() {
        cli = AfterwordCLI.locate()
        refreshNotes()
    }

    var notesFolder: NotesFolder { NotesFolder(directory: config.notesDirectory) }

    /// Looks for the CLI again (e.g. after following the setup steps), then reads its config
    /// and templates.
    func reload() async {
        cli = AfterwordCLI.locate()
        await loadConfig()
        await loadTemplates()
    }

    func loadConfig() async {
        guard let cli else { return }
        // If the config can't be read, keep what we had: `afterword record` would hit the same
        // problem and report it, and the Settings window shows the error.
        if let config = try? await cli.config() {
            apply(config)
        }
    }

    /// Takes a config the Settings window just saved.
    func apply(_ config: AfterwordConfig) {
        self.config = config
        refreshNotes()
    }

    func refreshNotes() {
        recentNotes = notesFolder.recentNotes()
    }

    func loadTemplates() async {
        guard let cli else { return }
        do {
            templates = try await cli.templates()
        } catch {
            templates = NoteTemplate.builtIn
        }
    }

    // MARK: Recording

    func startRecording(title: String, participants: [String], template: String, micOnly: Bool) {
        guard let cli, run == nil else { return }

        var arguments = ["record", "--template", template]
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty {
            arguments += ["--title", trimmedTitle]
        }
        for name in participants {
            arguments += ["--with", name]
        }
        if micOnly {
            arguments.append("--mic-only")
        }

        let process = cli.makeProcess(arguments: arguments)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let exitStatuses: AsyncStream<Int32>
        do {
            exitStatuses = try launch(process)
        } catch {
            phase = .failed(details: "Couldn't start afterword: \(error.localizedDescription)")
            return
        }

        let run = Run(process: process, title: trimmedTitle.isEmpty ? "Untitled conversation" : trimmedTitle)
        self.run = run
        phase = .starting
        Notifier.requestPermission()

        Task { await followOutput(of: output.fileHandleForReading, for: run) }
        Task { await collectErrors(from: errors.fileHandleForReading, for: run) }
        Task {
            let status = await exitStatuses.firstValue()
            // The exit status is the end of the run, not the pipes closing. Anything the CLI
            // started can inherit its pipes and hold them open long after it exits (an
            // after_note hook that runs `sync &`, say), so give the readers a moment to catch
            // the CLI's last lines and then stop waiting on them.
            _ = await waitUntil(timeout: .seconds(1)) { run.openPipes == 0 }
            finish(run, status: status)
        }
    }

    /// Ctrl+C, the same as in the terminal: the CLI stops the capture helper, then writes notes.
    func stopRecording() {
        guard let run, phase.isCapturing, run.stopRequest == nil, run.process.isRunning else { return }
        run.stopRequest = phase == .starting ? .cancelBeforeRecording : .stop
        run.process.interrupt()
        phase = .writingNotes(progress: "Stopping…")
    }

    /// Back to the form after a finished or failed recording.
    func dismissResult() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    /// Reacts to the CLI's stdout lines (see run_record in src/afterword/cli.py).
    private func followOutput(of handle: FileHandle, for run: Run) async {
        for await line in handle.arrivingLines {
            handleOutputLine(line.trimmingCharacters(in: .whitespaces), from: run)
        }
        run.openPipes -= 1
    }

    private func handleOutputLine(_ line: String, from run: Run) {
        guard run === self.run, !line.isEmpty else { return }

        if line.hasPrefix("Session folder: ") {
            run.sessionDirectory = String(line.dropFirst("Session folder: ".count))
            return
        }
        if line.hasPrefix("Recording.") {
            // After Stop or Cancel, this line can still be on its way; don't flip back.
            if run.stopRequest == nil {
                phase = .recording(since: .now)
            }
            return
        }
        if line.hasPrefix("Saved ") {
            run.savedNote = URL(fileURLWithPath: String(line.dropFirst("Saved ".count)))
        }
        // Once stopped, every line is progress worth showing ("Transcribing Me…", "Writing notes…").
        // The CLI can also stop on its own, e.g. if the capture helper fails mid-call.
        if phase.isWritingNotes || line == "Stopped recording." {
            phase = .writingNotes(progress: line)
        }
    }

    /// Collects stderr, keeping only the end: that's where Python puts the error that matters.
    private func collectErrors(from handle: FileHandle, for run: Run, keeping limit: Int = 12) async {
        for await line in handle.arrivingLines {
            run.errorLines.append(line)
            if run.errorLines.count > limit { run.errorLines.removeFirst() }
        }
        run.openPipes -= 1
    }

    private func finish(_ run: Run, status: Int32) {
        guard run === self.run else { return }
        self.run = nil
        refreshNotes()

        if status == 0 {
            let note = run.savedNote ?? notesFolder.newestNote
            phase = .finished(note: note)
            lastNotification = Notifier.post(title: "Notes ready", body: run.title, noteURL: note)
            return
        }

        // Cancelled before anything was recorded: nothing went wrong, so nothing to report.
        if run.stopRequest == .cancelBeforeRecording {
            phase = .idle
            return
        }

        let details = run.errorLines.isEmpty ? "afterword exited with status \(status)." : run.errorLines.joined(separator: "\n")
        phase = .failed(details: details)
        if isQuitting, let sessionDirectory = run.sessionDirectory {
            lastNotification = Notifier.post(
                title: "Notes for \(run.title) weren't finished",
                body: "Afterword quit first. The recording is saved; run: afterword process \"\(sessionDirectory)\"",
                noteURL: nil
            )
        } else {
            lastNotification = Notifier.post(title: "Afterword couldn't finish the notes", body: run.title, noteURL: nil)
        }
    }

    // MARK: Quitting

    /// How long quitting waits for notes to finish before giving up on them. Long enough for a
    /// short call's notes; for a long one the recording is kept and `afterword process` finishes it.
    private static let notesGracePeriod: Duration = .seconds(120)

    /// Called when the app is asked to quit while the CLI is running. Stops the recording,
    /// gives the notes a bounded chance to finish, then makes sure no `afterword record` is left
    /// behind. A crash or force quit skips this.
    func stopBeforeQuitting() async {
        guard let run else { return }
        isQuitting = true
        stopRecording()  // Does nothing if the recording already stopped and notes are being written.
        await waitForExit(of: run)
        // The app exits as soon as this returns, so let the last notification (notes ready, or
        // how to finish them) reach the system first.
        await lastNotification?.value
    }

    private func waitForExit(of run: Run) async {
        if await waitUntil(timeout: Self.notesGracePeriod, { self.run == nil }) { return }

        // Ctrl+C again: the CLI abandons the notes but keeps the saved recording.
        if run.process.isRunning { run.process.interrupt() }
        if await waitUntil(timeout: .seconds(10), { self.run == nil }) { return }

        if run.process.isRunning { run.process.terminate() }
        _ = await waitUntil(timeout: .seconds(2)) { self.run == nil }
    }

    /// Checks `condition` a few times a second until it holds or `timeout` passes.
    /// Returns whether it held.
    private func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    // MARK: Opening files

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openNotesFolder() {
        // The folder only exists after the first note; create it so the button always works.
        try? FileManager.default.createDirectory(at: config.notesDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(config.notesDirectory)
    }
}
