import SwiftUI

/// The Settings window: a front end for `afterword config`.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Group {
            if model.cli == nil {
                SetupNeededView { Task { await model.recorder.reload(); await model.load() } }
                    .padding(20)
            } else if case .failed(let message) = model.loadState {
                ConfigLoadFailedView(message: message) { Task { await model.load() } }
            } else {
                TabView {
                    GeneralSettings(model: model)
                        .tabItem { Label("General", systemImage: "gearshape") }
                    NotesWriterSettings(model: model)
                        .tabItem { Label("Notes Writer", systemImage: "sparkles") }
                    TranscriptionSettings(model: model)
                        .tabItem { Label("Transcription", systemImage: "waveform") }
                    JoplinSettings(model: model)
                        .tabItem { Label("Joplin", systemImage: "square.and.arrow.up") }
                    ScriptSettings(model: model)
                        .tabItem { Label("Scripts", systemImage: "terminal") }
                }
                .disabled(model.loadState == .loading)
                // Grouped forms draw text fields borderless, so they read as labels, not boxes to type in.
                .textFieldStyle(.roundedBorder)
            }
        }
        .frame(width: 520)
        .task { await model.load() }
        .onDisappear { Task { await model.flushPendingSaves() } }
    }
}

/// A setting's error from the CLI, shown right under the control it belongs to.
struct SettingError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A short explanation under a setting.
struct SettingHint: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ConfigLoadFailedView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't read your settings", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Fix ~/.config/afterword/config.toml in a text editor, then try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again", action: onRetry)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: General

struct GeneralSettings: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                FolderSetting(title: "Notes folder", key: "notes_dir", keyPath: \.notesDir, model: model)
                FolderSetting(title: "Recordings folder", key: "sessions_dir", keyPath: \.sessionsDir, model: model)
                SettingHint("Each recording's audio, transcript and summary go in a folder here.")
            }
            Section {
                Picker("Default template", selection: model.choice(\.template, key: "template")) {
                    ForEach(model.recorder.templates) { template in
                        Text(template.name).tag(template.name)
                    }
                }
                SettingError(message: model.errors["template"])
                Toggle("Remind me to ask before recording", isOn: model.toggle(\.consentReminder, key: "consent_reminder"))
                SettingHint("Shows a short consent reminder under the Record button.")
            }
        }
        .formStyle(.grouped)
    }
}

/// A folder path with a Choose… button.
struct FolderSetting: View {
    let title: String
    let key: String
    let keyPath: WritableKeyPath<AfterwordConfig, String>
    let model: SettingsModel

    @State private var isChoosing = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(NSString(string: model.draft[keyPath: keyPath]).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(model.draft[keyPath: keyPath])
                Button("Choose…") { isChoosing = true }
            }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            model.setFolder(url, key: key, keyPath: keyPath)
        }
        SettingError(message: model.errors[key])
    }
}

// MARK: Notes writer

struct NotesWriterSettings: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Writer", selection: model.choice(\.summarizer.provider, key: "summarizer.provider")) {
                    Text("Claude API").tag("anthropic")
                    Text("Claude Code").tag("claude-cli")
                    Text("Ollama (local)").tag("ollama")
                }
                SettingHint(providerHint)
                SettingError(message: model.errors["summarizer.provider"])
            }
            Section {
                TextField("Model", text: model.text(\.summarizer.model, key: "summarizer.model"), prompt: Text("Default"))
                SettingHint("Leave blank to use the writer's default model.")
                SettingError(message: model.errors["summarizer.model"])
            }
        }
        .formStyle(.grouped)
    }

    private var providerHint: LocalizedStringKey {
        switch model.draft.summarizer.provider {
        case "anthropic":
            "Pay per use with the Claude API. Needs an `ANTHROPIC_API_KEY` or a one-time `ant auth login`."
        case "claude-cli":
            "Uses Claude Code and your Claude subscription. Claude Code needs to be installed and signed in."
        case "ollama":
            "Runs on this Mac with Ollama: free and offline. Ollama needs to be running with the model downloaded."
        default:
            ""
        }
    }
}

// MARK: Transcription

struct TranscriptionSettings: View {
    let model: SettingsModel

    /// Sizes are the download sizes on Hugging Face.
    private static let speechModels = [
        PresetChoice(value: "base", label: "Fastest, least accurate (148 MB)"),
        PresetChoice(value: "small", label: "Fast (488 MB)"),
        PresetChoice(value: "large-v3-turbo-q5_0", label: "Balanced, recommended (574 MB)"),
        PresetChoice(value: "large-v3-turbo", label: "Most accurate (1.6 GB)"),
    ]

    private static let languages = [
        PresetChoice(value: "auto", label: "Detect automatically"),
        PresetChoice(value: "en", label: "English"),
        PresetChoice(value: "es", label: "Spanish"),
        PresetChoice(value: "fr", label: "French"),
        PresetChoice(value: "de", label: "German"),
        PresetChoice(value: "it", label: "Italian"),
        PresetChoice(value: "pt", label: "Portuguese"),
        PresetChoice(value: "nl", label: "Dutch"),
        PresetChoice(value: "ja", label: "Japanese"),
        PresetChoice(value: "ko", label: "Korean"),
        PresetChoice(value: "zh", label: "Chinese"),
        PresetChoice(value: "hi", label: "Hindi"),
    ]

    var body: some View {
        Form {
            Section {
                PresetPicker(
                    title: "Speech model",
                    choices: Self.speechModels,
                    otherLabel: "Other model name",
                    selection: model.text(\.whisperModel, key: "whisper_model")
                )
                SettingHint("Bigger models are more accurate but slower. A new model downloads the first time it's used.")
                SettingError(message: model.errors["whisper_model"])
            }
            Section {
                PresetPicker(
                    title: "Language",
                    choices: Self.languages,
                    otherLabel: "Language code",
                    selection: model.text(\.language, key: "language")
                )
                SettingHint("The language spoken on your calls. Picking it is more reliable than detecting it.")
                SettingError(message: model.errors["language"])
            }
        }
        .formStyle(.grouped)
    }
}

struct PresetChoice: Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

/// A picker of common values, plus "Other…" with a text field for anything else,
/// such as a whisper.cpp model name or language code that isn't in the list.
struct PresetPicker: View {
    let title: String
    let choices: [PresetChoice]
    let otherLabel: String
    @Binding var selection: String

    /// Set when the user picks "Other…", so the text field shows even before they type.
    @State private var choseOther = false

    private static let otherTag = "\u{0}other"

    private var isOther: Bool {
        choseOther || !choices.contains { $0.value == selection }
    }

    var body: some View {
        Picker(title, selection: pickerSelection) {
            ForEach(choices) { choice in
                Text(choice.label).tag(choice.value)
            }
            Divider()
            Text("Other…").tag(Self.otherTag)
        }
        if isOther {
            TextField(otherLabel, text: $selection)
        }
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: { isOther ? Self.otherTag : selection },
            set: { newValue in
                choseOther = newValue == Self.otherTag
                if !choseOther {
                    selection = newValue
                }
            }
        )
    }
}

// MARK: Joplin

struct JoplinSettings: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Send each note to Joplin", isOn: model.exportsToJoplin)
                SettingError(message: model.errors["exporters"])
            }
            Section {
                SecureField("Token", text: model.text(\.joplin.token, key: "joplin.token"))
                SettingHint("In Joplin: Settings → Web Clipper → Advanced options.")
                SettingError(message: model.errors["joplin.token"])
                TextField("Notebook", text: model.text(\.joplin.notebook, key: "joplin.notebook"))
                SettingError(message: model.errors["joplin.notebook"])
                TextField("Address", text: model.text(\.joplin.url, key: "joplin.url"))
                SettingError(message: model.errors["joplin.url"])
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Button("Test Connection") { Task { await model.testJoplin() } }
                        .disabled(model.joplinTest == .running)
                    JoplinTestResult(test: model.joplinTest)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct JoplinTestResult: View {
    let test: SettingsModel.JoplinTest

    var body: some View {
        switch test {
        case .notRun:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .finished(let connected, let message):
            Label(message, systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(connected ? .green : .red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: After-note scripts

struct ScriptSettings: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach($model.scripts) { $script in
                    HStack {
                        TextField("Command", text: $script.command, prompt: Text("~/bin/file-note"))
                            .labelsHidden()
                            .font(.body.monospaced())
                        Button {
                            model.removeScript(script)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove command")
                    }
                }
                Button("Add Command", systemImage: "plus", action: model.addScript)
                SettingError(message: model.errors["after_note"])
            } footer: {
                SettingHint("Shell commands run after each note is written. They get `AFTERWORD_NOTE`, `AFTERWORD_SESSION_DIR` and `AFTERWORD_TITLE` as environment variables.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.scripts) { model.saveScripts() }
    }
}
