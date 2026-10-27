import SwiftUI

/// The choices for "Write Notes Again": the session's own template, or any other one. The
/// transcript is reused, so only the notes are written again.
struct WriteNotesAgainItems: View {
    let templates: [NoteTemplate]
    /// nil means the template the session already uses.
    let onWrite: (_ template: String?) -> Void

    var body: some View {
        Button("Same Template") { onWrite(nil) }
        Section("With Another Template") {
            ForEach(templates) { template in
                Button(template.name) { onWrite(template.name) }
            }
        }
    }
}
