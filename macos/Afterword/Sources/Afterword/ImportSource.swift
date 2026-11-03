import Foundation

/// What was picked in Import Audio…'s panel: one recording to import, or a session folder
/// Afterword recorded itself.
///
/// A session folder matters because a recording whose notes failed has no note, so Recent
/// Notes can't offer Write Notes Again for it once its failure is dismissed. Importing the
/// folder writes its notes from the saved tracks, keeping the Me/Them split; importing just
/// its mic.m4a or system.m4a would lose the other side of the call.
enum ImportSource: Equatable {
    case audioFile(URL)
    /// Notes are written again from its saved tracks, as Write Notes Again does.
    case session(SessionToRewrite)
    /// A folder Afterword can't write notes from. `reason` says why, for the alert.
    case unusableFolder(reason: String)

    struct SessionToRewrite: Equatable {
        let directory: String
        let title: String
        /// The template it was recorded with, used unless another is chosen. nil if
        /// session.json doesn't say; `afterword process` then reports what's wrong.
        let template: String?
    }

    /// `sessionsDirectory` is only named in the message for a folder that isn't a session.
    init(picked url: URL, sessionsDirectory: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            self = .audioFile(url)
            return
        }

        let name = url.lastPathComponent
        guard let sessionFile = SessionFolder.sessionFile(at: url.path) else {
            let sessions = NSString(string: sessionsDirectory).abbreviatingWithTildeInPath
            self = .unusableFolder(
                reason: "“\(name)” isn't an Afterword session folder: it has no session.json Afterword can read. Choose an audio file, or a session's folder in \(sessions)."
            )
            return
        }
        guard sessionFile.hasRecording else {
            self = .unusableFolder(reason: "The session “\(sessionFile.title)” has no recording in it, so there's nothing to write notes from. It probably stopped before any audio was captured.")
            return
        }
        self = .session(SessionToRewrite(directory: url.path, title: sessionFile.title, template: sessionFile.template))
    }
}
