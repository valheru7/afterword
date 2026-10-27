import AppKit
import SwiftUI

/// The app's one small window, for the New Recording and Import forms, setup, and a failed
/// run's details.
///
/// It's an AppKit window hosting SwiftUI rather than a SwiftUI `Window` scene: a scene can open
/// by itself at launch, and the modifier that stops that (`defaultLaunchBehavior`) needs
/// macOS 15. A menu bar app also isn't active, so the window has to be brought to the front.
final class AppWindows {
    private var window: NSWindow?

    func showNewRecording(recorder: Recorder) {
        show(title: "New Recording") {
            SessionForm(mode: .record, recorder: recorder, onDone: close)
        }
    }

    /// Picks the file first, then shows the form for the rest.
    func showImport(recorder: Recorder) {
        NSApplication.shared.activate()
        let panel = NSOpenPanel()
        panel.message = "Choose a recording to write notes from."
        panel.prompt = "Choose"
        panel.allowedContentTypes = SessionForm.importableTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url else { return }

        show(title: "Import Audio") {
            SessionForm(mode: .importFile(file), recorder: recorder, onDone: close)
        }
    }

    func showFailureDetails(details: String, sessionDirectory: String?, recorder: Recorder) {
        show(title: "Notes Failed") {
            FailureDetailsView(
                details: details,
                sessionDirectory: sessionDirectory,
                templates: recorder.templates,
                onWriteAgain: { [self] template in
                    if let sessionDirectory {
                        recorder.writeNotesAgain(sessionDirectory: sessionDirectory, title: nil, template: template)
                    }
                    close()
                },
                onDone: { [self] in
                    recorder.dismissResult()
                    close()
                }
            )
        }
    }

    func close() {
        window?.close()
    }

    private func show<Content: View>(title: String, @ViewBuilder content: () -> Content) {
        let hosting = NSHostingController(rootView: content())
        // The window takes the size the SwiftUI content asks for.
        hosting.sizingOptions = [.preferredContentSize]

        let window = self.window ?? makeWindow()
        window.contentViewController = hosting
        window.title = title
        if !window.isVisible {
            window.center()
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        // Kept and reused, so closing it doesn't free it out from under us.
        window.isReleasedWhenClosed = false
        return window
    }
}
