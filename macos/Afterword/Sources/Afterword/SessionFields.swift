import SwiftUI

/// What you tell Afterword about a conversation: its title, who was on it, and the template.
/// Shared by the recording and import forms.
struct SessionDetails {
    var title = ""
    /// Names as typed, separated by commas.
    var participants = ""
    /// nil until you pick one, so the default follows the config even if it loads (or changes
    /// in Settings) after the form appears.
    var chosenTemplate: String?

    func template(defaultTemplate: String) -> String {
        chosenTemplate ?? defaultTemplate
    }

    var participantNames: [String] {
        participants
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct SessionFields: View {
    @Binding var details: SessionDetails
    let templates: [NoteTemplate]
    let defaultTemplate: String
    var titlePrompt = "Acme – hiring manager"

    var body: some View {
        TextField("Title", text: $details.title, prompt: Text(titlePrompt))
        TextField("With", text: $details.participants, prompt: Text("Names, separated by commas"))
        Picker("Template", selection: templateSelection) {
            ForEach(templates) { template in
                Text(template.name).tag(template.name)
            }
        }
        .help(selectedTemplateDescription)
    }

    private var template: String { details.template(defaultTemplate: defaultTemplate) }

    private var templateSelection: Binding<String> {
        Binding(get: { template }, set: { details.chosenTemplate = $0 })
    }

    private var selectedTemplateDescription: String {
        templates.first { $0.name == template }?.description ?? ""
    }
}
