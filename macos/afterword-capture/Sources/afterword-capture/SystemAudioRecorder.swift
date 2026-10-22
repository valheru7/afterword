import AVFoundation
import CoreAudio

/// Records everything the Mac plays (the other people on a Zoom, Meet or Teams call) through a
/// Core Audio process tap. Taps only need the "System Audio Recording" permission, not screen
/// recording, and they work with any call app because they sit below it.
final class SystemAudioRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: TrackWriter?

    func start(writingTo url: URL) throws {
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted  // You still hear the call normally.
        try check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "create the system audio tap")

        var streamDescription = try tapStreamDescription()
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError("The system audio tap reported a format AVFoundation can't read.")
        }

        // A tap can't be read directly. It has to be wrapped in a private aggregate device
        // that's clocked by the current output device.
        let outputUID = try defaultOutputDeviceUID()
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Afterword System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID),
            "create the aggregate device for the tap"
        )

        let writer = try TrackWriter(url: url, format: format)
        self.writer = writer
        let queue = DispatchQueue(label: "afterword.system-audio")
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, queue) { @Sendable _, inputData, inputTime, _, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData) else { return }
                writer.write(buffer, hostTime: inputTime.pointee.mHostTime)
            },
            "attach to the aggregate device"
        )
        try check(AudioDeviceStart(aggregateDeviceID, ioProcID), "start recording system audio")
    }

    /// Stops recording and tears down the tap. Returns the first buffer's host time in seconds.
    func stop() throws -> Double? {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        return try writer?.finish()
    }

    private func tapStreamDescription() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &description), "read the tap's audio format")
        return description
    }

    private func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID),
            "find the default output device"
        )

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid), "read the output device's ID")
        guard let uid else { throw CaptureError("The default output device has no ID.") }
        return uid.takeRetainedValue() as String
    }
}

private func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else {
        throw CaptureError("Couldn't \(action) (Core Audio error \(status)).")
    }
}
