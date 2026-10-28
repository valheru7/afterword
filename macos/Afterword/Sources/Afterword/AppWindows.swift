import AppKit
import SwiftUI

/// The app's windows: one small window for the New Recording and Import forms, setup, and a
/// failed run's details, and the Settings window.
///
/// It's an AppKit window hosting SwiftUI rather than a SwiftUI `Window` scene: a scene can open
/// by itself at launch, and the modifier that stops that (`defaultLaunchBehavior`) needs
/// macOS 15. A menu bar app also isn't active, so the window has to be brought to the front.
/// Settings gets the same treatment: SwiftUI's `openSettings` sometimes does nothing in an app
/// with no Dock icon, notably when its window is already open behind other apps.
final class AppWindows {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?

    func showNewRecording(recorder: Recorder) {
        show(title: "New Recording") {
            SessionForm(mode: .record, recorder: recorder, onDone: close)
        }
    }

    /// Picks the file first, then shows the form for the rest.
    func showImport(recorder: Recorder) {
        NSApplication.shared.activate(ignoringOtherApps: true)
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
                    // The window can outlive its failure: another run may have started from the
                    // menu since it opened. Only clear the failure it's showing, never a newer result.
                    if recorder.phase == .failed(details: details, sessionDirectory: sessionDirectory) {
                        recorder.dismissResult()
                    }
                    close()
                }
            )
        }
    }

    /// Reuses the one Settings window, so a second click brings it forward instead of opening
    /// another. Each time it opens it gets a fresh view, whose `.task` reloads the config:
    /// it may have changed in Terminal since, and editing stale values would overwrite that.
    func showSettings(model: SettingsModel) {
        let window = settingsWindow ?? makeSettingsWindow(model: model)
        settingsWindow = window
        if !window.isVisible {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            hosting.sizingOptions = [.preferredContentSize]
            window.contentViewController = hosting
            window.center()
        }
        bringToFront(window)
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
        bringToFront(window)
        self.window = window
    }

    private func makeSettingsWindow(model: SettingsModel) -> NSWindow {
        let window = makeWindow()
        window.title = "Afterword Settings"
        // SwiftUI's onDisappear doesn't fire when an AppKit window closes, so save what was
        // just typed from here instead of waiting for the debounce.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                _ = Task { await model.flushPendingSaves() }
            }
        }
        return window
    }

    /// A menu bar app is never the active app, and since macOS 14 `activate()` only asks:
    /// clicking a menu item doesn't count as the user switching apps, so the request can be
    /// refused and the window opens behind everything else. Ignoring other apps forces it,
    /// which is what the user asked for by choosing the menu item.
    private func bringToFront(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
