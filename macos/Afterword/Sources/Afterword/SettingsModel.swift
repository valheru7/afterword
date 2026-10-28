import Foundation
import Observation
import SwiftUI

/// Backs the Settings window. Every change is saved straight away with
/// `afterword config set`, so there's no Save button and the CLI validates everything.
@Observable
final class SettingsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    enum JoplinTest: Equatable {
        case notRun
        case running
        case finished(connected: Bool, message: String)
    }

    /// One after-note command, with an identity that survives edits so the list rows stay put.
    struct Script: Identifiable, Equatable {
        let id = UUID()
        var command: String
    }

    /// What the window shows and edits. A rejected value stays here (with its error) so you can
    /// fix it, while `saved` keeps what's really in the file.
    var draft = AfterwordConfig.defaults
    var scripts: [Script] = []
    private(set) var saved = AfterwordConfig.defaults
    private(set) var loadState = LoadState.loading
    /// The CLI's message for each setting it refused, by key (e.g. "joplin.url").
    private(set) var errors: [String: String] = [:]
    private(set) var joplinTest = JoplinTest.notRun

    let recorder: Recorder

    /// Text fields save once you pause typing, rather than on every keystroke.
    private var pendingSaves: [String: (value: String, timer: Task<Void, Never>)] = [:]
    /// Saves run one at a time. Each `config set` reads, changes and rewrites the whole file,
    /// so two at once could lose one of the changes.
    private var saveQueue: Task<Void, Never>?
    private var savesInFlight = 0

    /// Settings that are typed but not yet written to the file.
    var hasUnsavedChanges: Bool { !pendingSaves.isEmpty || savesInFlight > 0 }

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    var cli: AfterwordCLI? { recorder.cli }

    func load() async {
        guard let cli else { return }
        // Disables the form until the fresh values are in, so nothing typed into the old
        // ones (shown for a moment when Settings reopens) is overwritten by the reload.
        loadState = .loading
        await flushPendingSaves()
        do {
            let config = try await cli.config()
            saved = config
            draft = config
            scripts = config.afterNote.map { Script(command: $0) }
            errors = [:]
            loadState = .loaded
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }

    // MARK: Bindings that save

    /// A binding to one setting in `draft`. Setting it saves the value, right away or (for
    /// typing) after a short pause.
    func binding<Value>(
        _ keyPath: WritableKeyPath<AfterwordConfig, Value>,
        key: String,
        savesWhileTyping: Bool = false,
        encode: @escaping (Value) -> String
    ) -> Binding<Value> {
        Binding(
            get: { self.draft[keyPath: keyPath] },
            set: { newValue in
                self.draft[keyPath: keyPath] = newValue
                if savesWhileTyping {
                    self.saveAfterPause(key, encode(newValue))
                } else {
                    self.save(key, encode(newValue))
                }
            }
        )
    }

    func text(_ keyPath: WritableKeyPath<AfterwordConfig, String>, key: String) -> Binding<String> {
        binding(keyPath, key: key, savesWhileTyping: true) { $0 }
    }

    func choice(_ keyPath: WritableKeyPath<AfterwordConfig, String>, key: String) -> Binding<String> {
        binding(keyPath, key: key) { $0 }
    }

    func toggle(_ keyPath: WritableKeyPath<AfterwordConfig, Bool>, key: String) -> Binding<Bool> {
        binding(keyPath, key: key) { $0 ? "true" : "false" }
    }

    /// Joplin export is on when "joplin" is in `exporters`.
    var exportsToJoplin: Binding<Bool> {
        Binding(
            get: { self.draft.exporters.contains("joplin") },
            set: { isOn in
                var exporters = self.draft.exporters.filter { $0 != "joplin" }
                if isOn { exporters.append("joplin") }
                self.draft.exporters = exporters
                self.save("exporters", Self.jsonArray(exporters))
            }
        )
    }

    /// Folders are stored with ~ when they're in your home folder, as you'd type them.
    func setFolder(_ url: URL, key: String, keyPath: WritableKeyPath<AfterwordConfig, String>) {
        draft[keyPath: keyPath] = url.path
        save(key, NSString(string: url.path).abbreviatingWithTildeInPath)
    }

    // MARK: After-note scripts

    func addScript() {
        scripts.append(Script(command: ""))
    }

    func removeScript(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        saveScripts(afterPause: false)
    }

    /// Blank rows are left out, so a just-added row isn't saved until it has a command.
    func saveScripts(afterPause: Bool = true) {
        let commands = scripts
            .map { $0.command.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard commands != saved.afterNote || errors["after_note"] != nil else { return }
        if afterPause {
            saveAfterPause("after_note", Self.jsonArray(commands))
        } else {
            save("after_note", Self.jsonArray(commands))
        }
    }

    // MARK: Joplin

    func testJoplin() async {
        guard let cli else { return }
        joplinTest = .running
        // Test what's on screen, including a token typed a moment ago.
        await flushPendingSaves()
        await saveQueue?.value
        do {
            let result = try await cli.testJoplin()
            joplinTest = .finished(connected: result.connected, message: result.message)
        } catch {
            joplinTest = .finished(connected: false, message: error.localizedDescription)
        }
    }

    // MARK: Saving

    private func saveAfterPause(_ key: String, _ value: String) {
        pendingSaves[key]?.timer.cancel()
        let timer = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            pendingSaves[key] = nil
            save(key, value)
        }
        pendingSaves[key] = (value, timer)
    }

    /// Saves anything still waiting out its pause, e.g. when the window closes.
    func flushPendingSaves() async {
        let pending = pendingSaves
        pendingSaves = [:]
        for (key, entry) in pending {
            entry.timer.cancel()
            save(key, entry.value)
        }
        await saveQueue?.value
    }

    private func save(_ key: String, _ value: String) {
        guard let cli else { return }
        let previous = saveQueue
        savesInFlight += 1
        saveQueue = Task {
            await previous?.value
            do {
                try await cli.setConfig(key, to: value, isSecret: key == "joplin.token")
                errors[key] = nil
                await reloadSaved()
            } catch {
                errors[key] = error.localizedDescription
            }
            savesInFlight -= 1
        }
    }

    /// Writes what's been typed before the app quits, waiting at most `timeout` so a stuck
    /// CLI can't stop the app from quitting.
    func saveBeforeQuitting(timeout: Duration = .seconds(5)) async {
        guard hasUnsavedChanges else { return }
        Task { await flushPendingSaves() }
        let deadline = ContinuousClock.now + timeout
        while hasUnsavedChanges, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Re-reads the file after a save so the menu (recent notes, default template, consent
    /// reminder) follows right away. `draft` is left alone so nothing you're typing jumps.
    private func reloadSaved() async {
        guard let cli, let config = try? await cli.config() else { return }
        saved = config
        recorder.apply(config)
    }

    private static func jsonArray(_ values: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes  // Keeps paths readable in errors.
        let data = (try? encoder.encode(values)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
