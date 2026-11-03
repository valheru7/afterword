import SwiftUI

/// Shown when Import Audio… is given a session folder: confirms which session's notes will be
/// written again, and with which template. Closes when the run starts; the menu follows it.
struct ImportSessionView: View {
    let session: ImportSource.SessionToRewrite
    let recorder: Recorder
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(session.title, systemImage: "folder")
                .font(.headline)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                // Clicking uses the session's own template; the arrow offers the others,
                // like the failure window's Write Notes Again.
                Menu {
                    WriteNotesAgainItems(templates: recorder.templates, onWrite: write)
                } label: {
                    Text("Write Notes")
                } primaryAction: {
                    write(template: nil)
                }
                .fixedSize()
                // Another recording or note is still running; the menu shows which.
                .disabled(recorder.phase.isBusy)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var explanation: String {
        let template = session.template.map { "the “\($0)” template it was recorded with" } ?? "the template it was recorded with"
        return "This is a session Afterword recorded. Its notes are written again from its saved Me and Them tracks, "
            + "reusing any saved transcript, with \(template). The arrow next to Write Notes offers other templates."
    }

    private func write(template: String?) {
        recorder.writeNotesAgain(sessionDirectory: session.directory, title: session.title, template: template)
        onDone()
    }
}
