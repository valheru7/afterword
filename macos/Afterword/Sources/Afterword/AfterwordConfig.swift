import Foundation

/// The CLI's settings, as `afterword config show --json` prints them: defaults filled in and
/// paths expanded. Python owns the keys, defaults and file format; this only mirrors them.
struct AfterwordConfig: Decodable, Equatable {
    struct Summarizer: Decodable, Equatable {
        var provider: String
        var model: String
    }

    struct Joplin: Decodable, Equatable {
        var token: String
        var notebook: String
        var url: String
    }

    var sessionsDir: String
    var notesDir: String
    var template: String
    var consentReminder: Bool
    var whisperModel: String
    var language: String
    var summarizer: Summarizer
    var exporters: [String]
    var joplin: Joplin
    var afterNote: [String]

    var notesDirectory: URL { URL(fileURLWithPath: notesDir, isDirectory: true) }

    /// Used until the CLI answers, and when it isn't installed. Matches src/afterword/config.py.
    static let defaults = AfterwordConfig(
        sessionsDir: NSString(string: "~/Afterword/sessions").expandingTildeInPath,
        notesDir: NSString(string: "~/Afterword/notes").expandingTildeInPath,
        template: "meeting",
        consentReminder: true,
        whisperModel: "large-v3-turbo-q5_0",
        language: "en",
        summarizer: Summarizer(provider: "anthropic", model: ""),
        exporters: [],
        joplin: Joplin(token: "", notebook: "Afterword", url: "http://localhost:41184"),
        afterNote: []
    )

    static func decode(fromJSON data: Data) throws -> AfterwordConfig {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AfterwordConfig.self, from: data)
    }
}
