import Foundation
import FluidAudio

/// Parakeet TDT v3 (Core ML, Neural Engine): batch decode of VAD-cut utterances,
/// 25 European languages including Ukrainian. Leaves the GPU to the local LLM.
public actor ParakeetRecognitionService {
    private var manager: AsrManager?
    private var busy = false
    public init() {}
    public var ready: Bool { manager != nil }
    public static var folder: URL { LocalPaths.models.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true) }
    public static var installed: Bool { AsrModels.modelsExist(at: folder, version: .v3) }
    public func download() async throws {
        guard !busy else { throw CopilotError.message("Parakeet is busy") }; busy = true; defer { busy = false }
        _ = try await AsrModels.download(to: Self.folder, version: .v3)
    }
    public func load() async throws {
        if manager != nil { return }
        guard !busy else { throw CopilotError.message("Parakeet is busy") }; busy = true; defer { busy = false }
        guard Self.installed else { throw CopilotError.message("Download Parakeet once in Speech Recognition settings") }
        let models = try await AsrModels.load(from: Self.folder, version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }
    public func unload() async { await manager?.cleanup(); manager = nil }
    public func transcribe(_ samples: [Float], language: String, vocabulary: String = "") async throws -> SpeechResult {
        guard !busy else { throw CopilotError.message("Parakeet is busy") }
        guard let manager else { throw CopilotError.message("Parakeet is not loaded") }
        busy = true; defer { busy = false }
        try Task.checkCancellation()
        let start = Date()
        // Parakeet has no prompt conditioning; vocabulary is applied later by TechnicalQuestionNormalizer.
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &state, language: Language(rawValue: language))
        try Task.checkCancellation()
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpeechResult(text: SpeechRecognitionService.isSpeechText(text) ? text : "", seconds: Date().timeIntervalSince(start))
    }
    public func transcribeFile(path: String, language: String) async throws -> SpeechResult {
        try await transcribe(AudioConverter().resampleAudioFile(path: path), language: language)
    }
}

/// Sends pipeline decodes to the engine selected in settings.
public actor SpeechEngineRouter {
    private let whisper: SpeechRecognitionService
    private let parakeet: ParakeetRecognitionService
    private var useParakeet = false
    public init(whisper: SpeechRecognitionService, parakeet: ParakeetRecognitionService) { self.whisper = whisper; self.parakeet = parakeet }
    public func select(parakeet: Bool) { useParakeet = parakeet }
    public func transcribe(_ samples: [Float], language: String, vocabulary: String) async throws -> SpeechResult {
        useParakeet ? try await parakeet.transcribe(samples, language: language) : try await whisper.transcribe(samples, language: language, vocabulary: vocabulary)
    }
}
