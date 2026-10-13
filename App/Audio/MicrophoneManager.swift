import AVFoundation
import CoreAudio
import AudioToolbox
import LocalCopilotCore

struct MicrophoneDevice: Identifiable, Equatable { let id: UInt32; let name: String }
@MainActor final class MicrophoneManager {
    private(set) var activeDeviceName = "Не активний"
    private var stream: MicrophoneStream?
    private var observers: [NSObjectProtocol] = []
    var onConfigurationChange: (() -> Void)?
    static func devices() -> [MicrophoneDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &name)
            return MicrophoneDevice(id: id, name: name?.takeRetainedValue() as String? ?? "Microphone")
        }
    }
    static func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return "Невідомий пристрій" }
        return name?.takeRetainedValue() as String? ?? "Невідомий пристрій"
    }
    static func inputDeviceName(_ id: AudioDeviceID) -> String {
        // AVAudioEngine wraps the default input in a private aggregate. Show its real input members.
        var address = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return deviceName(id) }
        var members = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &members) == noErr else { return deviceName(id) }
        let names = members.filter { member in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            return member != id && AudioObjectGetPropertyDataSize(member, &streams, 0, nil, &bytes) == noErr && bytes > 0
        }.map { deviceName($0) }
        return names.isEmpty ? deviceName(id) : names.joined(separator: ", ")
    }
    static func routeSignature() -> String {
        [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice].map { selector in
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
            address.mSelector = kAudioDevicePropertyNominalSampleRate
            var rate: Float64 = 0; size = UInt32(MemoryLayout<Float64>.size)
            _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate)
            return "\(id):\(rate)"
        }.joined(separator: "|")
    }
    static func defaultDeviceName(output: Bool) -> String {
        var address = AudioObjectPropertyAddress(mSelector: output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return "Не визначено" }
        return deviceName(id)
    }
    static func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    func start(deviceID: UInt32, output: @escaping @Sendable (AudioFrame) -> Void) async throws {
        stop()
        try await PermissionsManager.microphone()
        let devices = AVCaptureDevice.devices(for: .audio)
        let device: AVCaptureDevice?
        if deviceID == 0 { device = AVCaptureDevice.default(for: .audio) }
        else {
            guard Self.devices().contains(where: { $0.id == deviceID }) else { throw CopilotError.message("Selected microphone is disconnected. Select an available device.") }
            let uid = Self.deviceUID(deviceID)
            device = devices.first { $0.uniqueID == uid }
        }
        guard let device else { throw CopilotError.message("Microphone unavailable. Select System Default or another input.") }
        let stream = MicrophoneStream(output: output)
        try await stream.start(device: device)
        self.stream = stream; activeDeviceName = device.localizedName
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: stream.session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onConfigurationChange?() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onConfigurationChange?() }
        })
    }
    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
        stream?.stop(); stream = nil
    }
}
// CaptureSession supports explicit input selection without modifying the global
// output route or the AVAudioEngine private aggregate. Its blocking start/stop
// and sample conversion run on one dedicated queue, never the UI executor.
private final class MicrophoneStream: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Questionio.microphone")
    private let converter = AudioPCMConverter()
    private let output: @Sendable (AudioFrame) -> Void
    init(output: @escaping @Sendable (AudioFrame) -> Void) { self.output = output }
    func start(device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    let data = AVCaptureAudioDataOutput()
                    guard self.session.canAddInput(input), self.session.canAddOutput(data) else { throw CopilotError.message("Cannot configure microphone capture") }
                    self.session.beginConfiguration(); self.session.addInput(input); self.session.addOutput(data)
                    data.setSampleBufferDelegate(self, queue: self.queue)
                    self.session.commitConfiguration(); self.session.startRunning()
                    guard self.session.isRunning else { throw CopilotError.message("Microphone capture could not start") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func stop() { queue.async { self.session.stopRunning() } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let samples = converter.convert(sampleBuffer)
        if !samples.isEmpty { self.output(AudioFrame(samples: samples, source: .microphone)) }
    }
}
