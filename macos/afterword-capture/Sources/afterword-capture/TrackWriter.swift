import AVFoundation

/// Appends audio buffers to one compressed file and remembers when the first buffer arrived,
/// so the Python side can line the "me" and "them" tracks up on a shared clock.
///
/// Core Audio and AVAudioEngine call `write` from their own background threads, and `finish`
/// comes from the main actor, so every access goes through `lock`.
nonisolated final class TrackWriter: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var firstHostTime: UInt64?
    private var writeError: Error?

    init(url: URL, format: AVAudioFormat) throws {
        self.url = url
        // AAC keeps an hour of speech around 40 MB instead of over a gigabyte of raw PCM.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64_000 * Int(format.channelCount),
        ]
        file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
    }

    func write(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, writeError == nil else { return }
        if firstHostTime == nil, hostTime != 0 {
            firstHostTime = hostTime
        }
        do {
            try file.write(from: buffer)
        } catch {
            // Keep the first error; the recording is reported as failed when it stops.
            writeError = error
        }
    }

    /// Closes the file and returns when the first buffer arrived, in host-clock seconds.
    func finish() throws -> Double? {
        lock.lock()
        defer { lock.unlock() }
        file = nil  // AVAudioFile flushes and closes on release.
        if let writeError { throw writeError }
        return firstHostTime.map { AVAudioTime.seconds(forHostTime: $0) }
    }
}
