import Foundation
import LocalCopilotCore
@MainActor final class AudioCaptureManager {
    let microphone = MicrophoneManager()
    let system = SystemAudioManager()
    private var continuation: AsyncStream<AudioFrame>.Continuation?
    private var emitFrame: (@Sendable (AudioFrame) -> Void)?
    var droppedFrames = 0
    var microphoneRetryAllowed = true
    var microphoneActive = false
    var systemActive = false
    var systemRetryAllowed = true
    var onFailure: ((AudioSource, String) -> Void)?
    var onDrop: (() -> Void)?
    func start(settings: CopilotSettings) async throws -> AsyncStream<AudioFrame> {
        await stop()
        droppedFrames = 0; systemRetryAllowed = true; microphoneRetryAllowed = true
        // A short Core Audio burst or a busy UI must not erase a whole utterance.
        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(512))
        self.continuation = continuation
        let output: @Sendable (AudioFrame) -> Void = { [weak self] frame in
            if case .dropped = continuation.yield(frame) {
                Task { @MainActor in
                    guard let self else { return }
                    self.droppedFrames += 1
                    if self.droppedFrames == 1 || self.droppedFrames % 50 == 0 { self.onDrop?() }
                }
            }
        }
        emitFrame = output
        var failures: [String] = []
        // Initialize the input route before starting the high-frequency system tap.
        // AirPods input setup may take seconds; buffering system audio through it
        // would discard the beginning of the first utterance before consumption starts.
        if settings.effectiveAudioMode != .system {
            do { try await microphone.start(deviceID: settings.microphoneID, output: output); microphoneActive = true }
            catch { microphoneRetryAllowed = PermissionsManager.microphoneAuthorized; failures.append(error.localizedDescription); onFailure?(.microphone, error.localizedDescription) }
        }
        if settings.effectiveAudioMode != .microphone {
            do {
                try await system.start(applicationID: settings.applicationID, backend: settings.audioBackend, output: output) { [weak self] reason in
                    Task { @MainActor in self?.systemActive = false; self?.onFailure?(.system, reason) }
                }; systemActive = true
            } catch { systemRetryAllowed = false; failures.append(error.localizedDescription); onFailure?(.system, error.localizedDescription) }
        }
        guard microphoneActive || systemActive else { continuation.finish(); self.continuation = nil; throw CopilotError.message(failures.joined(separator: "\n")) }
        microphone.onConfigurationChange = { [weak self] in
            self?.microphoneActive = false; self?.microphoneRetryAllowed = true
            self?.onFailure?(.microphone, "Audio device configuration changed. Reconnecting…")
        }
        return stream
    }
    func reconnectMicrophone(settings: CopilotSettings) async throws {
        guard let emitFrame else { return }
        try await microphone.start(deviceID: settings.microphoneID, output: emitFrame)
        microphoneActive = true
    }
    func reconnectSystem(settings: CopilotSettings) async throws {
        guard let emitFrame else { return }
        do { try await system.start(applicationID: settings.applicationID, backend: settings.audioBackend, output: emitFrame) { [weak self] reason in
            Task { @MainActor in self?.systemActive = false; self?.onFailure?(.system, reason) }
        }
        systemActive = true
        } catch { systemRetryAllowed = false; throw error }
    }
    func stop() async {
        continuation?.finish(); continuation = nil
        emitFrame = nil
        microphone.stop(); await system.stop(); microphoneActive = false; systemActive = false
    }
}
