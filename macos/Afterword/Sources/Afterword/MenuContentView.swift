import SwiftUI

/// Everything in the menu bar window: the current recording state, recent notes, and app actions.
struct MenuContentView: View {
    let recorder: Recorder

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recorder.cli == nil {
                SetupNeededView { Task { await recorder.reload() } }
            } else {
                phaseView
            }

            Divider()
            RecentNotesView(notes: recorder.recentNotes, open: recorder.open)
            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuRowButton("Open Notes Folder", systemImage: "folder", action: recorder.openNotesFolder)
                MenuRowButton("Settings…", systemImage: "gearshape") {
                    // A menu bar app isn't active, so its windows would open behind others.
                    NSApplication.shared.activate()
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                // Quitting while busy stops the recording and gives the notes a while to finish
                // (see AppDelegate.applicationShouldTerminate).
                MenuRowButton(recorder.phase.isCapturing ? "Stop and Quit" : "Quit Afterword", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        // The menu can open before launch finished loading; this covers that, and the CLI
        // being installed while the app was running.
        .task { await recorder.reload() }
        // The window is reused each time the menu opens, so refresh then: notes may have been
        // written from the terminal in the meantime.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            recorder.refreshNotes()
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch recorder.phase {
        case .idle:
            NewRecordingForm(recorder: recorder)
        case .starting:
            StartingView(onCancel: recorder.stopRecording)
        case .recording(let since):
            RecordingView(since: since, onStop: recorder.stopRecording)
        case .writingNotes(let progress):
            WritingNotesView(progress: progress)
        case .finished(let note):
            FinishedView(note: note, open: recorder.open, onDone: recorder.dismissResult)
        case .failed(let details):
            FailedView(details: details, onDone: recorder.dismissResult)
        }
    }
}

/// A full-width, menu-style row button for the window's footer.
struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}
