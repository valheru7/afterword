import Foundation

/// What one line of the CLI's stdout means to the app (see run_record, run_import and
/// process_session in src/afterword).
enum RunEvent: Equatable {
    /// "Session folder: PATH". Where the recording is saved, so the notes can be retried.
    case sessionFolder(String)
    /// "Recording.": the capture helper is running.
    case recordingStarted
    /// "Saved PATH": the note's file. Also shown as progress, like any other line.
    case savedNote(URL, line: String)
    /// Anything else, e.g. "Transcribing Me…" or "Writing notes…".
    case progress(String)

    /// Nil for a blank line.
    init?(line: String) {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }

        if line.hasPrefix("Session folder: ") {
            self = .sessionFolder(String(line.dropFirst("Session folder: ".count)))
        } else if line.hasPrefix("Recording.") {
            self = .recordingStarted
        } else if line.hasPrefix("Saved ") {
            self = .savedNote(URL(fileURLWithPath: String(line.dropFirst("Saved ".count))), line: line)
        } else {
            self = .progress(line)
        }
    }
}

extension Recorder.Phase {
    /// The phase after the CLI says `event`. `stopRequested` is whether Stop or Cancel was
    /// pressed; `now` is when a recording counts as started.
    func after(_ event: RunEvent, stopRequested: Bool, now: Date) -> Self {
        switch event {
        case .sessionFolder:
            return self
        case .recordingStarted:
            // After Stop or Cancel, this line can still be on its way; don't flip back.
            return stopRequested ? self : .recording(since: now)
        case .savedNote(_, let line), .progress(let line):
            // Once stopped, every line is progress worth showing ("Transcribing Me…", "Writing
            // notes…"). The CLI can also stop on its own, e.g. if the capture helper fails mid-call.
            if isWritingNotes || line == "Stopped recording." {
                return .writingNotes(progress: line)
            }
            return self
        }
    }
}
