import SwiftUI

struct StartingView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting…").font(.headline)
            }
            Text("The first time, macOS asks for microphone and system audio permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Stop", action: onCancel)
        }
    }
}

struct RecordingView: View {
    let since: Date
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Recording").font(.headline)
                Spacer()
                // A timer-style Text updates itself every second without any state of ours.
                Text(since, style: .timer)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Elapsed time")
            }
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}

struct WritingNotesView: View {
    let progress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Writing notes…").font(.headline)
            }
            Text(progress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("This can take a few minutes. You'll get a notification when the notes are ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FinishedView: View {
    let note: URL?
    let open: (URL) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes ready", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            HStack {
                if let note {
                    Button("Open Note") { open(note) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button("New Recording", action: onDone)
            }
        }
    }
}

struct FailedView: View {
    let details: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Afterword couldn't finish", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ScrollView {
                Text(details)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            Text("If the recording was saved, `afterword process SESSION_DIR` in Terminal can retry the notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("OK", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct SetupNeededView: View {
    let onCheckAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Afterword isn't installed yet", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text("This app runs the `afterword` command, which it couldn't find on your PATH, in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin. Follow the Install (macOS) steps in the README, then check again.")
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

struct RecentNotesView: View {
    let notes: [RecentNote]
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if notes.isEmpty {
                Text("Notes you record show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                Button { open(note.url) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title).lineLimit(1)
                        Text(note.modified, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
    }
}
