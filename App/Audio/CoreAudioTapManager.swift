import AppKit
import CoreAudio
import AVFoundation
import LocalCopilotCore

/// Audio-only public macOS API. Private tap/device exist only during capture.
@available(macOS 14.2, *)
@MainActor final class CoreAudioTapManager {
    private var tapID: AudioObjectID = 0
    private var deviceID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "Questionio.audio.tap", qos: .userInitiated)
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    static func processes() throws -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList); var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "List audio processes")
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try result.withUnsafeMutableBytes { bytes in try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!), "Read audio processes") }
        return result
    }
    private static func pid(_ object: AudioObjectID) -> pid_t {
        var address = address(kAudioProcessPropertyPID); var size = UInt32(MemoryLayout<pid_t>.size); var result: pid_t = 0
        _ = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result); return result
    }
    private static func bundleID(_ object: AudioObjectID) -> String {
        var address = address(kAudioProcessPropertyBundleID); var size = UInt32(MemoryLayout<CFString?>.size); var result: CFString?
        _ = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return result as String? ?? ""
    }
    static func applications() -> [AudioApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else { return nil }
            return AudioApplication(bundleID: id, name: app.localizedName ?? id)
        }.sorted { $0.name < $1.name }
    }
    func start(applicationID: String, output: @escaping @Sendable (AudioFrame) -> Void) throws {
        stop()
        do {
            let objects = try Self.processes()
            let description: CATapDescription
            if applicationID.isEmpty {
                let own = objects.filter { Self.pid($0) == ProcessInfo.processInfo.processIdentifier }
                description = CATapDescription(stereoGlobalTapButExcludeProcesses: own)
            } else {
                let selected = objects.filter { Self.bundleID($0) == applicationID || Self.bundleID($0).hasPrefix(applicationID + ".") }
                guard !selected.isEmpty else { throw CopilotError.message("Selected application has no audio process yet. Play audio in it, then press Start.") }
                description = CATapDescription(stereoMixdownOfProcesses: selected)
            }
            description.name = "Questionio audio only"; description.uuid = UUID(); description.isPrivate = true; description.muteBehavior = .unmuted
            try Self.check(AudioHardwareCreateProcessTap(description, &tapID), "Create audio tap")
            var formatDescription = AudioStreamBasicDescription()
            var address = Self.address(kAudioTapPropertyFormat); var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &formatDescription), "Read tap format")
            guard let format = AVAudioFormat(streamDescription: &formatDescription) else { throw CopilotError.message("Unsupported system audio format") }
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Questionio private audio capture",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID), "Create private audio device")
            let converter = AudioPCMConverter()
            let bytesPerFrame = formatDescription.mBytesPerFrame
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, queue) { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let first = buffers.first, first.mData != nil, bytesPerFrame > 0 else { return }
                let frames = AVAudioFrameCount(first.mDataByteSize / bytesPerFrame)
                guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                pcm.frameLength = frames
                let destination = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
                for index in 0..<min(buffers.count, destination.count) {
                    guard let source = buffers[index].mData, let target = destination[index].mData else { continue }
                    memcpy(target, source, min(Int(buffers[index].mDataByteSize), Int(destination[index].mDataByteSize)))
                }
                let samples = converter.convert(pcm)
                if !samples.isEmpty { output(AudioFrame(samples: samples, source: .system)) }
            }, "Register audio callback")
            try Self.check(AudioDeviceStart(deviceID, ioProc), "Start system audio; enable Questionio in System Audio Recording Only if denied")
        } catch { stop(); throw error }
    }
    func stop() {
        if deviceID != 0 {
            if let ioProc { AudioDeviceStop(deviceID, ioProc); AudioDeviceDestroyIOProcID(deviceID, ioProc) }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        ioProc = nil; deviceID = 0
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }; tapID = 0
    }
    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw CopilotError.message("\(operation) failed (Core Audio \(status)). Check audio permission and selected source; ScreenCaptureKit is available in Audio settings.") }
    }
}
