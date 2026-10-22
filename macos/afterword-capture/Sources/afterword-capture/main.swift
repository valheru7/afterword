// afterword-capture: records your microphone and the Mac's system audio to separate files
// until it receives SIGINT or SIGTERM, then writes capture.json describing the tracks.
//
// Usage: afterword-capture --out <directory> [--no-system] [--no-mic]
//
// The Python `afterword record` command runs this; you normally don't call it yourself.

import Foundation

struct CaptureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    var outputDirectory: URL
    var recordsSystemAudio = true
    var recordsMicrophone = true

    init(arguments: [String]) throws {
        var outputPath: String?
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--out": outputPath = remaining.popFirst()
            case "--no-system": recordsSystemAudio = false
            case "--no-mic": recordsMicrophone = false
            default: throw CaptureError("Unknown argument: \(argument)")
            }
        }
        guard let outputPath else { throw CaptureError("Missing --out <directory>.") }
        guard recordsSystemAudio || recordsMicrophone else {
            throw CaptureError("Nothing to record: both --no-system and --no-mic were passed.")
        }
        outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
    }
}

/// One line of JSON on stdout per event, so the Python side can follow along.
func emit(_ event: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: event),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
    fflush(stdout)
}

/// Delivers Ctrl+C (SIGINT) and SIGTERM as values instead of killing the process, so the
/// recorders can shut down cleanly instead of dying mid-write. Create it before starting the
/// recorders: a signal that arrives while permission prompts are up is buffered, not lost.
func makeStopSignals() -> AsyncStream<Int32> {
    AsyncStream<Int32> { continuation in
        let sources = [SIGINT, SIGTERM].map { stopSignal in
            signal(stopSignal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: stopSignal, queue: .main)
            source.setEventHandler { continuation.yield(stopSignal) }
            source.resume()
            return source
        }
        // The termination handler also keeps the sources alive for as long as the stream is.
        continuation.onTermination = { _ in sources.forEach { $0.cancel() } }
    }
}

func run() async throws {
    let stopSignals = makeStopSignals()
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

    let microphone = options.recordsMicrophone ? MicrophoneRecorder() : nil
    let systemAudio = options.recordsSystemAudio ? SystemAudioRecorder() : nil
    let micURL = options.outputDirectory.appendingPathComponent("mic.m4a")
    let systemURL = options.outputDirectory.appendingPathComponent("system.m4a")

    // The first run triggers macOS permission prompts (microphone, system audio recording);
    // starting blocks until they're answered.
    emit(["event": "starting"])
    try await microphone?.start(writingTo: micURL)
    if microphone != nil { emit(["event": "microphone-started"]) }
    try systemAudio?.start(writingTo: systemURL)
    emit(["event": "recording"])

    for await _ in stopSignals { break }

    var tracks: [[String: Any]] = []
    if let microphone {
        let start = try microphone.stop()
        tracks.append(["role": "me", "file": micURL.lastPathComponent, "start_seconds": start ?? NSNull()])
    }
    if let systemAudio {
        let start = try systemAudio.stop()
        tracks.append(["role": "them", "file": systemURL.lastPathComponent, "start_seconds": start ?? NSNull()])
    }

    let manifest: [String: Any] = ["tracks": tracks]
    let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try manifestData.write(to: options.outputDirectory.appendingPathComponent("capture.json"))
    emit(["event": "stopped"])
}

do {
    try await run()
} catch {
    emit(["event": "error", "message": "\(error)"])
    exit(1)
}
