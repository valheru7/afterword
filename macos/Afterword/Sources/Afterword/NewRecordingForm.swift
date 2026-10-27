import SwiftUI

/// The idle state: what `afterword record --title … --with … --template …` would take.
struct NewRecordingForm: View {
    let recorder: Recorder

    @State private var title = ""
    @State private var participants = ""
    /// nil until you pick one, so the default follows the config even if it loads (or changes
    /// in Settings) after the form appears.
    @State private var chosenTemplate: String?
    @State private var micOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Recording")
                .font(.headline)

            TextField("Title", text: $title, prompt: Text("Acme – hiring manager"))
            TextField("With", text: $participants, prompt: Text("Names, separated by commas"))

            Picker("Template", selection: templateSelection) {
                ForEach(recorder.templates) { template in
                    Text(template.name).tag(template.name)
                }
            }
            .help(selectedTemplateDescription)

            Toggle("Only record my microphone", isOn: $micOnly)
                .help("For when someone on the call would rather not be recorded.")

            if recorder.config.consentReminder {
                Text("Ask everyone if it's OK to record first. Many places require everyone's consent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                recorder.startRecording(
                    title: title,
                    participants: participantNames,
                    template: template,
                    micOnly: micOnly
                )
            } label: {
                Label("Record", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var template: String { chosenTemplate ?? recorder.config.template }

    private var templateSelection: Binding<String> {
        Binding(get: { template }, set: { chosenTemplate = $0 })
    }

    private var participantNames: [String] {
        participants
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var selectedTemplateDescription: String {
        recorder.templates.first { $0.name == template }?.description ?? ""
    }
}
