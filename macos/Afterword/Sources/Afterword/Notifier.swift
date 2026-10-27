import AppKit
import UserNotifications

/// Posts "Notes ready" notifications. Writing notes takes minutes, so you're usually somewhere
/// else when it finishes; clicking the notification opens the note.
enum Notifier {
    nonisolated private static let notePathKey = "notePath"

    /// Asked when you first press Record, the moment the reason for it is obvious.
    static func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Returns the task handing the notification to the system; await it if the app is about
    /// to exit, or the notification can be lost.
    @discardableResult
    static func post(title: String, body: String, noteURL: URL?) -> Task<Void, Never> {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let noteURL {
            content.userInfo = [notePathKey: noteURL.path]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        return Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    nonisolated static func notePath(in response: UNNotificationResponse) -> String? {
        response.notification.request.content.userInfo[notePathKey] as? String
    }
}
