import AVFoundation

/// Records the default input device (your microphone) on its own track, so the transcript
/// can label "me" and "them" without guessing at speakers.
final class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private var writer: TrackWriter?

    func start(writingTo url: URL) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw CaptureError(
                "Microphone access is off. Turn it on for your terminal app in "
                    + "System Settings → Privacy & Security → Microphone."
            )
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw CaptureError("No microphone found.")
        }

        let writer = try TrackWriter(url: url, format: format)
        self.writer = writer
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, time in
            writer.write(buffer, hostTime: time.hostTime)
        }
        try engine.start()
    }

    /// Stops recording. Returns the first buffer's host time in seconds.
    func stop() throws -> Double? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return try writer?.finish()
    }
}
