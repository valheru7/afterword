import Foundation
import Testing
@testable import Afterword

struct ImportSourceTests {
    private let sessionsDirectory = "/tmp/afterword/sessions"

    /// A fresh, empty folder for one test.
    private func makeFolder(_ name: String = "2026-11-02-0930-acme") throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Written the way session.py's `Session.save()` writes it.
    private func writeSessionFile(_ json: String, in folder: URL) throws {
        try Data(json.utf8).write(to: folder.appendingPathComponent("session.json"))
    }

    @Test func `an audio file is imported as before`() throws {
        let file = try makeFolder().appendingPathComponent("memo.m4a")
        try Data("audio".utf8).write(to: file)

        #expect(ImportSource(picked: file, sessionsDirectory: sessionsDirectory) == .audioFile(file))
    }

    @Test func `a recorded session folder has its notes written again with its own template`() throws {
        let folder = try makeFolder()
        try writeSessionFile("""
            {
              "title": "Acme call",
              "template": "job-interview",
              "started_at": "2026-11-02T09:30:00-08:00",
              "participants": ["Dana Lee"],
              "tracks": [
                {"speaker": "Me", "file": "mic.m4a", "offset_seconds": 0.0},
                {"speaker": "Them", "file": "system.m4a", "offset_seconds": 0.15}
              ]
            }
            """, in: folder)

        let expected = ImportSource.SessionToRewrite(directory: folder.path, title: "Acme call", template: "job-interview")
        #expect(ImportSource(picked: folder, sessionsDirectory: sessionsDirectory) == .session(expected))
    }

    @Test func `a folder without session.json isn't a session`() throws {
        let folder = try makeFolder("Downloads")
        try Data("audio".utf8).write(to: folder.appendingPathComponent("memo.m4a"))

        guard case .unusableFolder(let reason) = ImportSource(picked: folder, sessionsDirectory: sessionsDirectory) else {
            Issue.record("Expected an unusable folder")
            return
        }
        #expect(reason.contains("“Downloads” isn't an Afterword session folder"))
        #expect(reason.contains(sessionsDirectory))
    }

    @Test func `a session that never captured audio has nothing to write notes from`() throws {
        let folder = try makeFolder()
        try writeSessionFile("""
            {"title": "Acme call", "template": "meeting", "started_at": "2026-11-02T09:30:00-08:00", "participants": [], "tracks": []}
            """, in: folder)

        guard case .unusableFolder(let reason) = ImportSource(picked: folder, sessionsDirectory: sessionsDirectory) else {
            Issue.record("Expected an unusable folder")
            return
        }
        #expect(reason.contains("has no recording"))
    }

    @Test func `an unreadable session.json isn't treated as a session`() throws {
        let folder = try makeFolder()
        try writeSessionFile("{ not json", in: folder)

        guard case .unusableFolder = ImportSource(picked: folder, sessionsDirectory: sessionsDirectory) else {
            Issue.record("Expected an unusable folder")
            return
        }
    }
}
