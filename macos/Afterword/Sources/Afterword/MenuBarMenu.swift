import SwiftUI

/// The menu bar menu: what's happening now, then ways to start something, recent notes and the
/// app's own items. Text items show as disabled status lines in a native menu.
struct MenuBarMenu: View {
    let recorder: Recorder
    let settings: SettingsModel
    let windows: AppWindows

    var body: some View {
        status
        startItems
        setupItems
        Divider()
        RecentNotesMenu(recorder: recorder)
        Button("Open Notes Folder", action: recorder.openNotesFolder)
        Divider()
        Button("Settings…") {
            windows.showSettings(model: settings)
        }
        .keyboardShortcut(",")
        // Quitting while busy stops the recording and gives the notes a while to finish
        // (see AppDelegate.applicationShouldTerminate).
        Button(recorder.phase.isCapturing ? "Stop and Quit" : "Quit Afterword") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: Status

    @ViewBuilder private var status: some View {
        switch recorder.phase {
        case .idle:
            EmptyView()
        case .starting:
            Text("Starting…")
            stopButton
            Divider()
        case .recording(let since):
            Text("● Recording \(elapsed(since: since))")
            stopButton
            Divider()
        case .writingNotes(let progress):
            Text("Writing notes…")
            Text(progress)
            Divider()
        case .finished(let note):
            if let note {
                Button("Notes Ready: Open Note") {
                    recorder.open(note)
                    recorder.dismissResult()
                }
            } else {
                Text("Notes ready")
            }
            Divider()
        case .failed(let details, let sessionDirectory):
            Button("Notes Failed: Show Details…") {
                windows.showFailureDetails(details: details, sessionDirectory: sessionDirectory, recorder: recorder)
            }
            if let sessionDirectory {
                Menu("Write Notes Again") {
                    WriteNotesAgainItems(templates: recorder.templates) { template in
                        recorder.writeNotesAgain(sessionDirectory: sessionDirectory, title: nil, template: template)
                    }
                }
            }
            Divider()
        }
    }

    private var stopButton: some View {
        Button("Stop Recording", action: recorder.stopRecording)
            .keyboardShortcut(".")
    }

    /// "12:34", or "1:02:03" past an hour. `recorder.now` ticks while recording.
    private func elapsed(since start: Date) -> String {
        let seconds = max(0, recorder.now.timeIntervalSince(start))
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }

    // MARK: Starting something

    @ViewBuilder private var startItems: some View {
        let canStart = recorder.cli != nil && !recorder.phase.isBusy
        Button("New Recording…") {
            recorder.dismissResult()
            windows.showNewRecording(recorder: recorder)
        }
        .keyboardShortcut("n")
        .disabled(!canStart)
        Button("Import Audio…") {
            recorder.dismissResult()
            windows.showImport(recorder: recorder)
        }
        .keyboardShortcut("i")
        .disabled(!canStart)
    }

    /// The CLI missing (a build without the bundled tools) or the speech model not downloaded.
    @ViewBuilder private var setupItems: some View {
        if recorder.cli == nil {
            Button("Set Up Afterword…") {
                windows.showNewRecording(recorder: recorder)  // The form shows the setup steps.
            }
        } else {
            switch recorder.speechModel {
            case .unknown, .ready:
                EmptyView()
            case .missing:
                Button("Download Speech Model (One Time)", action: recorder.downloadSpeechModel)
            case .downloading(let progress):
                Text(progress)
            case .failed:
                Button("Speech Model Download Failed: Try Again", action: recorder.downloadSpeechModel)
            }
        }
    }
}

/// Recent Notes ▸ each note ▸ Open, and Write Notes Again when its session can be rewritten.
struct RecentNotesMenu: View {
    let recorder: Recorder

    var body: some View {
        Menu("Recent Notes") {
            if recorder.recentNotes.isEmpty {
                Text("Notes you record show up here")
            }
            ForEach(recorder.recentNotes) { note in
                Menu(note.title) {
                    Button("Open") { recorder.open(note.url) }
                    if let sessionDirectory = note.sessionDirectory {
                        Menu("Write Notes Again") {
                            WriteNotesAgainItems(templates: recorder.templates) { template in
                                recorder.writeNotesAgain(sessionDirectory: sessionDirectory, title: note.title, template: template)
                            }
                        }
                        .disabled(recorder.cli == nil || recorder.phase.isBusy)
                    }
                }
            }
        }
    }
}
