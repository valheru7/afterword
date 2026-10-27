import SwiftUI

@main
struct AfterwordApp: App {
    // The delegate owns the recorder because it also needs it when the app is asked to quit.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(recorder: appDelegate.recorder)
        } label: {
            MenuBarIcon(phase: appDelegate.recorder.phase)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.settings)
        }
    }
}

/// The menu bar icon. It turns red while the microphone may be live, so it's obvious at a glance
/// that a call is being recorded.
struct MenuBarIcon: View {
    let phase: Recorder.Phase

    var body: some View {
        switch phase {
        case .starting, .recording:
            Image(nsImage: .recordingIndicator)
                .accessibilityLabel("Afterword, recording")
        case .writingNotes:
            Image(systemName: "doc.text")
                .accessibilityLabel("Afterword, writing notes")
        case .idle, .finished, .failed:
            Image(systemName: "record.circle")
                .accessibilityLabel("Afterword")
        }
    }
}

extension NSImage {
    /// A red record symbol. Menu bar images are templates (drawn in the menu bar's color) unless
    /// they opt out, so this one sets `isTemplate = false` to keep its red.
    static let recordingIndicator: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
        let symbol = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        let image = symbol?.withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }()
}
