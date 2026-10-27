import Foundation

/// A note file in the notes folder.
struct RecentNote: Identifiable, Hashable {
    let url: URL
    let title: String
    let modified: Date

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

        let notes = files.compactMap { url -> RecentNote? in
            guard url.pathExtension == "md",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            let modified = values.contentModificationDate ?? .distantPast
            return RecentNote(url: url, title: Self.title(of: url), modified: modified)
        }
        return Array(notes.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    var newestNote: URL? { recentNotes(limit: 1).first?.url }

    /// The `title:` from the note's YAML header, falling back to the file name. Notes start with
    /// that header, so the first couple of kilobytes are enough.
    private static func title(of url: URL) -> String {
        let fallback = url.deletingPathExtension().lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: url) else { return fallback }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2048) else { return fallback }

        let header = String(decoding: data, as: UTF8.self)
        guard let titleLine = header.split(separator: "\n").first(where: { $0.hasPrefix("title: ") }) else {
            return fallback
        }
        // The CLI writes the title as a JSON string (a valid YAML string), escapes included.
        let encoded = titleLine.dropFirst("title: ".count)
        let title = try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))
        return title ?? fallback
    }
}
