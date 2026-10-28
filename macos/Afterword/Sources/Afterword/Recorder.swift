import AppKit
import Observation

/// Runs `afterword record`, `import` or `process` and follows it from start to finished note.
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
        /// `sessionDirectory` is set when the recording was saved, so the notes can be retried.
        case failed(details: String, sessionDirectory: String?)

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

    /// One CLI process and what it has told us so far. Each run gets its own object, so pipe
    /// readers that outlive their run (see `finish`) can't touch the next one.
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
        await checkSpeechModel()
    }

    /// The setup screen's Check Again button.
    func checkForCLIAgain() {
        Task { await reload() }
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
        let modelChanged = config.whisperModel != self.config.whisperModel
        self.config = config
        refreshNotes()
        if modelChanged {
            Task { await checkSpeechModel() }
        }
    }

    // MARK: Speech model

    /// The Whisper model is several hundred MB, too big to ship in the app, so it's downloaded
    /// once into the CLI's cache. This lets you do that before the first call instead of after.
    enum SpeechModelState: Equatable {
        case unknown
        case ready
        case missing
        case downloading(progress: String)
        case failed(message: String)
    }

    private(set) var speechModel = SpeechModelState.unknown

    func checkSpeechModel() async {
        guard let cli else { return }
        if case .downloading = speechModel { return }
        speechModel = await cli.isModelDownloaded() ? .ready : .missing
    }

    func downloadSpeechModel() {
        guard let cli else { return }
        if case .downloading = speechModel { return }
        speechModel = .downloading(progress: "Starting the download…")
        Task {
            do {
                try await cli.downloadModel { line in
                    speechModel = .downloading(progress: line)
                }
                speechModel = .ready
            } catch {
                speechModel = .failed(message: error.localizedDescription)
            }
        }
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

    // MARK: Recording, importing and rewriting notes

    /// What the New Recording and Import Audio forms start.
    enum SessionKind {
        case record
        /// Notes from a recording made some other way (a voice memo, a call another app recorded).
        case importFile(URL)
    }

    /// Whether New Recording, Import Audio and Write Notes Again can start something now.
    var canStartSession: Bool {
        cli != nil && !phase.isBusy
    }

    /// The form's Start Recording or Import button. Without a chosen template, the config's
    /// default is used; `micOnly` only applies to a recording.
    func startSession(_ kind: SessionKind, details: SessionDetails, micOnly: Bool) {
        let template = details.template(defaultTemplate: config.template)
        switch kind {
        case .record:
            startRecording(title: details.title, participants: details.participantNames, template: template, micOnly: micOnly)
        case .importFile(let file):
            importRecording(file, title: details.title, participants: details.participantNames, template: template)
        }
    }

    private func startRecording(title: String, participants: [String], template: String, micOnly: Bool) {
        var arguments = ["record", "--template=\(template)"] + Self.sessionArguments(title: title, participants: participants)
        if micOnly {
            arguments.append("--mic-only")
        }
        startRun(arguments, title: title, firstPhase: .starting)
    }

    /// `afterword import`: notes from a recording made some other way. There's nothing to stop,
    /// so it goes straight to writing notes.
    private func importRecording(_ file: URL, title: String, participants: [String], template: String) {
        // Without a title the CLI would say "Untitled conversation"; the file name says more.
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let title = trimmedTitle.isEmpty ? file.deletingPathExtension().lastPathComponent : trimmedTitle
        let arguments = ["import", file.path, "--template=\(template)"]
            + Self.sessionArguments(title: title, participants: participants)
        startRun(arguments, title: title, firstPhase: .writingNotes(progress: "Importing \(file.lastPathComponent)…"))
    }

    /// `afterword process`: writes a session's notes again, reusing its saved transcript.
    /// `template` nil keeps the one the session was recorded with. Without a `title` (for the
    /// notification), it's read from the session.
    func writeNotesAgain(sessionDirectory: String, title: String?, template: String?) {
        var arguments = ["process", sessionDirectory]
        if let template {
            arguments.append("--template=\(template)")
        }
        let title = title ?? SessionFolder.title(at: sessionDirectory) ?? "Untitled conversation"
        startRun(arguments, title: title, firstPhase: .writingNotes(progress: "Writing notes again…"), sessionDirectory: sessionDirectory)
    }

    /// The failure window's Write Notes Again. It only offers that when the recording was saved,
    /// so without a session folder there's nothing to do.
    func writeNotesAgain(afterFailureIn sessionDirectory: String?, template: String?) {
        guard let sessionDirectory else { return }
        writeNotesAgain(sessionDirectory: sessionDirectory, title: nil, template: template)
    }

    /// `--option=value`, never `--option value`: argparse would read a value that starts with a
    /// dash ("-Dana", "--no-process") as an option of its own.
    private static func sessionArguments(title: String, participants: [String]) -> [String] {
        var arguments: [String] = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty {
            arguments.append("--title=\(trimmedTitle)")
        }
        for name in participants {
            arguments.append("--with=\(name)")
        }
        return arguments
    }

    /// Starts the CLI and follows its output until it exits. Only one run at a time.
    private func startRun(_ arguments: [String], title: String, firstPhase: Phase, sessionDirectory: String? = nil) {
        guard let cli, run == nil else { return }

        let process = cli.makeProcess(arguments: arguments)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let exitStatuses: AsyncStream<Int32>
        do {
            exitStatuses = try launch(process)
        } catch {
            phase = .failed(details: "Couldn't start afterword: \(error.localizedDescription)", sessionDirectory: nil)
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let run = Run(process: process, title: trimmedTitle.isEmpty ? "Untitled conversation" : trimmedTitle)
        run.sessionDirectory = sessionDirectory
        self.run = run
        phase = firstPhase
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

    /// Back to the form after a finished or failed run.
    func dismissResult() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    /// The failure window's OK. The window can outlive its failure (another run may have
    /// started from the menu since it opened), so this only clears the failure it showed,
    /// never a newer result.
    func dismissFailure(details: String, sessionDirectory: String?) {
        guard phase == .failed(details: details, sessionDirectory: sessionDirectory) else { return }
        dismissResult()
    }

    /// The menu's Notes Ready item: opens the note and goes back to the form.
    func openFinishedNote(_ note: URL) {
        open(note)
        dismissResult()
    }

    /// Reacts to the CLI's stdout lines (see `RunEvent`).
    private func followOutput(of handle: FileHandle, for run: Run) async {
        for await line in handle.lines() {
            handleOutputLine(line, from: run)
        }
        run.openPipes -= 1
    }

    private func handleOutputLine(_ line: String, from run: Run) {
        guard run === self.run, let event = RunEvent(line: line) else { return }

        switch event {
        case .sessionFolder(let path):
            run.sessionDirectory = path
        case .savedNote(let note, _):
            run.savedNote = note
        case .recordingStarted, .progress:
            break
        }
        let nextPhase = phase.after(event, stopRequested: run.stopRequest != nil, now: .now)
        if nextPhase != phase {
            phase = nextPhase
        }
    }

    /// Collects stderr, keeping only the end: that's where Python puts the error that matters.
    private func collectErrors(from handle: FileHandle, for run: Run, keeping limit: Int = 12) async {
        for await line in handle.lines() {
            run.errorLines.append(line)
            if run.errorLines.count > limit { run.errorLines.removeFirst() }
        }
        run.openPipes -= 1
    }

    private func finish(_ run: Run, status: Int32) {
        guard run === self.run else { return }
        self.run = nil
        refreshNotes()
        // The CLI downloads the speech model before transcribing if it wasn't there yet.
        Task { await checkSpeechModel() }

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
        // A recording that failed before capturing anything has a session folder but nothing in
        // it to write notes from.
        let retryableSession = run.sessionDirectory.flatMap { SessionFolder.hasRecording(at: $0) ? $0 : nil }
        phase = .failed(details: details, sessionDirectory: retryableSession)
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

    /// Called when the app is asked to quit while the CLI is running. Stops a recording, gives
    /// the notes (from a recording, an import or a rewrite) a bounded chance to finish, then
    /// makes sure no CLI process is left behind. A crash or force quit skips this.
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
