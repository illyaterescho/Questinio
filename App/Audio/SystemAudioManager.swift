import ScreenCaptureKit
import CoreMedia
import LocalCopilotCore
struct AudioApplication: Identifiable, Hashable { var id: String { bundleID }; let bundleID: String; let name: String }
final class SystemAudioReceiver: NSObject, SCStreamOutput, SCStreamDelegate {
    let output: @Sendable (AudioFrame) -> Void
    let failure: @Sendable (String) -> Void
    private let converter = AudioPCMConverter()
    init(output: @escaping @Sendable (AudioFrame) -> Void, failure: @escaping @Sendable (String) -> Void) { self.output = output; self.failure = failure }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        let samples = converter.convert(sampleBuffer)
        if !samples.isEmpty { output(AudioFrame(samples: samples, source: .system)) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failure(error.localizedDescription) }
}
@MainActor final class SystemAudioManager {
    private var tap: Any?
    private var stream: SCStream?
    private var receiver: SystemAudioReceiver?
    private let queue = DispatchQueue(label: "Questionio.system.audio", qos: .userInitiated)
    static func applications(backend: String) async throws -> [AudioApplication] {
        if backend == "Core Audio Tap", #available(macOS 14.2, *) { return CoreAudioTapManager.applications() }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        var seen = Set<String>()
        return content.applications.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier && seen.insert($0.bundleIdentifier).inserted }.map { AudioApplication(bundleID: $0.bundleIdentifier, name: $0.applicationName) }.sorted { $0.name < $1.name }
    }
    func start(applicationID: String, backend: String, output: @escaping @Sendable (AudioFrame) -> Void, failure: @escaping @Sendable (String) -> Void) async throws {
        await stop()
        if backend == "Core Audio Tap", #available(macOS 14.2, *) {
            let tap = CoreAudioTapManager(); try tap.start(applicationID: applicationID, output: output); self.tap = tap; return
        }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        catch { throw CopilotError.message("System audio access failed: \(error.localizedDescription). Enable Questionio in Privacy & Security → Screen & System Audio Recording; restart the app if macOS requires it.") }
        guard let display = content.displays.first else { throw CopilotError.message("No display is available for ScreenCaptureKit") }
        let filter: SCContentFilter
        if applicationID.isEmpty {
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        } else {
            let selected = content.applications.filter { $0.bundleIdentifier == applicationID }
            guard !selected.isEmpty else { throw CopilotError.message("Selected application is not running. Open it or select another audio source.") }
            filter = SCContentFilter(display: display, including: selected, exceptingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000; config.channelCount = 2
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        // No screen output is registered or stored. Only audio callbacks are consumed.
        let receiver = SystemAudioReceiver(output: output, failure: failure)
        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: queue)
        do { try await stream.startCapture() } catch { throw CopilotError.message("ScreenCaptureKit cannot capture this source: \(error.localizedDescription)") }
        self.receiver = receiver; self.stream = stream
    }
    func stop() async { if #available(macOS 14.2, *), let tap = tap as? CoreAudioTapManager { tap.stop() }; tap = nil; let old = stream; stream = nil; receiver = nil; try? await old?.stopCapture() }
}
