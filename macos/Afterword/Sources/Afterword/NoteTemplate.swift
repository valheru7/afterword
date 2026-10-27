import Foundation

/// A note template, as listed by `afterword templates`.
struct NoteTemplate: Identifiable, Hashable {
    let name: String
    let description: String

    var id: String { name }

    /// Parses one line of `afterword templates`: the name, padding, then the description.
    init?(listingLine line: Substring) {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard let name = parts.first else { return nil }
        self.name = String(name)
        self.description = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    }

    init(name: String, description: String = "") {
        self.name = name
        self.description = description
    }

    /// The built-in templates, used when `afterword templates` can't be run. Custom templates
    /// won't show up then, but recording still works.
    static let builtIn = ["interview-recap", "job-interview", "meeting", "one-on-one"].map { NoteTemplate(name: $0) }
}
