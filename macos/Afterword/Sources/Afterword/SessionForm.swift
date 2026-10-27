import SwiftUI
import UniformTypeIdentifiers

/// The New Recording and Import Audio form: what `afterword record` or `afterword import`
/// takes. Closes when the run starts; the menu follows it from there.
struct SessionForm: View {
    enum Mode {
        case record
        /// Notes from a recording made some other way (a voice memo, a call another app recorded).
        case importFile(URL)
    }

    let mode: Mode
    let recorder: Recorder
    let onDone: () -> Void

    @State private var details = SessionDetails()
    @State private var micOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recorder.cli == nil {
                SetupNeededView { Task { await recorder.reload() } }
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 380)
        .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder private var form: some View {
        if case .importFile(let file) = mode {
            Label(file.lastPathComponent, systemImage: "waveform")
                .font(.headline)
        }

        SessionFields(
            details: $details,
            templates: recorder.templates,
            defaultTemplate: recorder.config.template,
            titlePrompt: titlePrompt
        )

        switch mode {
        case .record:
            Toggle("Only record my microphone", isOn: $micOnly)
                .help("For when someone on the call would rather not be recorded.")
            if recorder.config.consentReminder {
                Text("Ask everyone if it's OK to record first. Many places require everyone's consent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .importFile:
            Text("Without a title, the file's name is used. Video files work too.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        SpeechModelRow(state: recorder.speechModel, onDownload: recorder.downloadSpeechModel)

        HStack {
            Button("Cancel", action: onDone)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(startTitle, action: start)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // Another recording or note is still running; the menu shows which.
                .disabled(recorder.phase.isBusy)
        }
    }

    private var titlePrompt: String {
        switch mode {
        case .record: "Acme – hiring manager"
        case .importFile(let file): file.deletingPathExtension().lastPathComponent
        }
    }

    private var startTitle: String {
        switch mode {
        case .record: "Start Recording"
        case .importFile: "Import"
        }
    }

    private func start() {
        let template = details.template(defaultTemplate: recorder.config.template)
        switch mode {
        case .record:
            recorder.startRecording(title: details.title, participants: details.participantNames, template: template, micOnly: micOnly)
        case .importFile(let file):
            recorder.importRecording(file, title: details.title, participants: details.participantNames, template: template)
        }
        onDone()
    }

    /// What the bundled ffmpeg can read (see bundle-tools.sh): common audio files, and the audio
    /// track of MP4, QuickTime, Matroska and WebM videos.
    static let importableTypes: [UTType] = [
        "m4a", "mp3", "wav", "aif", "aiff", "flac", "caf", "aac", "opus", "ogg", "oga",
        "mp4", "m4v", "mov", "mkv", "webm",
    ].compactMap { UTType(filenameExtension: $0) }
}

/// Shown until the Whisper model is downloaded. Recording works without it; the CLI then
/// downloads it after the call, before transcribing.
struct SpeechModelRow: View {
    let state: Recorder.SpeechModelState
    let onDownload: () -> Void

    var body: some View {
        switch state {
        case .unknown, .ready:
            EmptyView()
        case .missing:
            VStack(alignment: .leading, spacing: 6) {
                Text("The speech model isn't downloaded yet. It's a one-time download of a few hundred MB; without it, it downloads after your first recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Download Speech Model", systemImage: "arrow.down.circle", action: onDownload)
            }
        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: onDownload)
            }
        }
    }
}
