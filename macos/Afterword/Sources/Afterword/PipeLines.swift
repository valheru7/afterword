import Foundation

extension FileHandle {
    /// Starts reading the handle and returns its lines as they arrive, ending when the other end
    /// closes. Call it once per handle: it takes over `readabilityHandler`, so a second call
    /// would take the data away from the first.
    ///
    /// `bytes.lines` can hold a pipe's output back until the pipe closes: the app sat on
    /// "Starting…" for a whole recording because the CLI's "Recording." line only got through
    /// once the CLI exited. `readabilityHandler` fires as soon as any data is written.
    nonisolated func lines() -> AsyncStream<String> {
        let (chunks, chunkContinuation) = AsyncStream.makeStream(of: Data.self)
        readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {  // End of file.
                handle.readabilityHandler = nil
                chunkContinuation.finish()
            } else {
                chunkContinuation.yield(data)
            }
        }

        return AsyncStream { lineContinuation in
            let splitter = Task {
                // A chunk can end partway through a line (or a multi-byte character), so keep
                // the unfinished part until its newline arrives.
                var pending = Data()
                for await chunk in chunks {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                        lineContinuation.yield(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    }
                }
                if !pending.isEmpty {
                    lineContinuation.yield(String(decoding: pending, as: UTF8.self))
                }
                lineContinuation.finish()
            }
            lineContinuation.onTermination = { _ in splitter.cancel() }
        }
    }
}
