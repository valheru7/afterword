import Foundation
import Testing
@testable import Afterword

struct RunEventTests {
    @Test(arguments: [
        ("Session folder: /Users/me/Afterword/sessions/2026-10-27 Acme", RunEvent.sessionFolder("/Users/me/Afterword/sessions/2026-10-27 Acme")),
        ("Recording.", .recordingStarted),
        ("Recording. Press Ctrl+C to stop.", .recordingStarted),
        ("Saved /Users/me/Afterword/notes/Acme.md", .savedNote(URL(fileURLWithPath: "/Users/me/Afterword/notes/Acme.md"), line: "Saved /Users/me/Afterword/notes/Acme.md")),
        ("Transcribing Me…", .progress("Transcribing Me…")),
        ("Stopped recording.", .progress("Stopped recording.")),
        ("  Writing notes…  ", .progress("Writing notes…")),
    ])
    func `parses a line`(line: String, expected: RunEvent) {
        #expect(RunEvent(line: line) == expected)
    }

    @Test(arguments: ["", "   "])
    func `ignores a blank line`(line: String) {
        #expect(RunEvent(line: line) == nil)
    }
}

struct PhaseAfterRunEventTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func `recording starts when the CLI says so`() {
        let phase = Recorder.Phase.starting.after(.recordingStarted, stopRequested: false, now: start)
        #expect(phase == .recording(since: start))
    }

    @Test func `a late recording line doesn't undo a stop`() {
        let stopping = Recorder.Phase.writingNotes(progress: "Stopping…")
        #expect(stopping.after(.recordingStarted, stopRequested: true, now: start) == stopping)
    }

    @Test(arguments: [
        Recorder.Phase.starting,
        .recording(since: Date(timeIntervalSince1970: 1_000)),
    ])
    func `progress before stopping isn't shown`(phase: Recorder.Phase) {
        #expect(phase.after(.progress("Capture helper ready"), stopRequested: false, now: start) == phase)
        #expect(phase.after(.sessionFolder("/tmp/session"), stopRequested: false, now: start) == phase)
    }

    @Test func `the CLI stopping on its own starts writing notes`() {
        let phase = Recorder.Phase.recording(since: start)
            .after(.progress("Stopped recording."), stopRequested: false, now: start)
        #expect(phase == .writingNotes(progress: "Stopped recording."))
    }

    @Test(arguments: [
        (RunEvent.progress("Transcribing Me…"), "Transcribing Me…"),
        (.savedNote(URL(fileURLWithPath: "/tmp/note.md"), line: "Saved /tmp/note.md"), "Saved /tmp/note.md"),
    ])
    func `while writing notes, each line is the progress`(event: RunEvent, shownLine: String) {
        let phase = Recorder.Phase.writingNotes(progress: "Stopping…")
            .after(event, stopRequested: true, now: start)
        #expect(phase == .writingNotes(progress: shownLine))
    }
}
