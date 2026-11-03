import Foundation

/// A note file in the notes folder.
struct RecentNote: Identifiable, Hashable {
    let url: URL
    let title: String
    let modified: Date
    /// The session folder the note was written from (its recording and saved transcript), or
    /// nil if the header doesn't name one or there's no longer a recording in it.
    let sessionDirectory: String?

    var id: URL { url }
}

/// Reads the notes folder the CLI writes to.
struct NotesFolder {
    let directory: URL

    /// The newest notes by modification date. Returns an empty list if the folder doesn't exist
    /// yet, which is normal before the first recording.
    func recentNotes(limit: Int = 5) -> [RecentNote] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        let noteFiles = files.compactMap { url -> (url: URL, modified: Date)? in
            guard url.pathExtension == "md",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }
        // This runs each time a menu opens, so only the newest notes' files are read, not
        // every note in the folder.
        let newest = noteFiles.sorted { $0.modified > $1.modified }.prefix(limit)
        return newest.map { file in
            let header = NoteHeader(of: file.url)
            return RecentNote(
                url: file.url,
                title: header.title ?? file.url.deletingPathExtension().lastPathComponent,
                modified: file.modified,
                sessionDirectory: header.session.flatMap { SessionFolder.hasRecording(at: $0) ? $0 : nil }
            )
        }
    }

    var newestNote: URL? { recentNotes(limit: 1).first?.url }
}

/// The fields we need from a note's YAML header (see `Note.markdown` in src/afterword/note.py).
struct NoteHeader {
    var title: String?
    var session: String?

    /// Notes start with the header, so the first couple of kilobytes are enough.
    init(of url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2048) else { return }

        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        title = Self.value(of: "title", in: lines)
        session = Self.value(of: "session", in: lines)
    }

    /// The CLI writes these values as JSON strings (valid YAML strings), escapes included.
    private static func value(of key: String, in lines: [Substring]) -> String? {
        let prefix = "\(key): "
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let encoded = line.dropFirst(prefix.count)
        return try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))
    }
}

/// A session folder the CLI wrote: session.json, the audio tracks and the saved transcript
/// (see src/afterword/session.py).
enum SessionFolder {
    /// The parts of session.json the app reads.
    struct SessionFile: Decodable {
        struct Track: Decodable {}
        let title: String
        /// The note template it was recorded (or last rewritten) with.
        let template: String?
        let tracks: [Track]?

        /// Whether `afterword process` can write notes from it: at least one recorded track.
        /// A recording that failed before capturing anything has none.
        var hasRecording: Bool { !(tracks ?? []).isEmpty }
    }

    static func hasRecording(at path: String) -> Bool {
        sessionFile(at: path)?.hasRecording ?? false
    }

    static func title(at path: String) -> String? {
        sessionFile(at: path)?.title
    }

    /// nil when the folder has no session.json, or one that can't be read.
    static func sessionFile(at path: String) -> SessionFile? {
        let file = URL(fileURLWithPath: path).appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SessionFile.self, from: data)
    }
}
