import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let recorder = Recorder()
    lazy var settings = SettingsModel(recorder: recorder)

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { await recorder.reload() }
    }

    /// Quitting mid-call would otherwise leave `afterword record` running with nobody to stop
    /// it. Stop it first, and let the notes finish if they can do so in reasonable time.
    /// On logout or restart, macOS doesn't wait that long: if we haven't replied within its own
    /// timeout it cancels the logout ("Afterword interrupted…"). The recording has still been
    /// stopped by then; only the notes keep the app running.
    ///
    /// Settings typed a moment ago may still be waiting to save. Those are written after the
    /// recording is stopped, so saving never delays stopping the microphone.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.phase.isBusy || settings.hasUnsavedChanges else { return .terminateNow }
        Task {
            await recorder.stopBeforeQuitting()
            await settings.saveBeforeQuitting()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // Show the banner even if the menu is open (the app counts as frontmost then).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let path = Notifier.notePath(in: response) else { return }
        await MainActor.run {
            _ = NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}
