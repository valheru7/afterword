import SwiftUI

/// The details of a failed run, with a way to write the notes again once the problem's fixed.
struct FailureDetailsView: View {
    let details: String
    let sessionDirectory: String?
    let templates: [NoteTemplate]
    let onWriteAgain: (_ template: String?) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Afterword couldn't finish the notes", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ScrollView {
                Text(details)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            if sessionDirectory != nil {
                Text("The recording is saved. Once the problem is fixed (in Settings, say), write the notes again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if sessionDirectory != nil {
                    // Clicking uses the same template; the arrow offers the others.
                    Menu {
                        WriteNotesAgainItems(templates: templates, onWrite: onWriteAgain)
                    } label: {
                        Text("Write Notes Again")
                    } primaryAction: {
                        onWriteAgain(nil)
                    }
                    .fixedSize()
                }
                Spacer()
                Button("OK", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

struct SetupNeededView: View {
    let onCheckAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Afterword isn't installed yet", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            // Only a build without the bundled tools (a bare `swift build`) gets here.
            Text("This copy of the app doesn't include the `afterword` command, and it couldn't find one on your PATH, in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin. Build the app with make-app.sh, or follow the Install (macOS) steps in the README, then check again.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Install Steps", destination: URL(string: "https://github.com/valheru7/afterword#install-macos")!)
                Spacer()
                Button("Check Again", action: onCheckAgain)
            }
        }
    }
}
