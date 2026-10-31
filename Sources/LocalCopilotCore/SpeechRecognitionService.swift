import Foundation
import WhisperKit

public struct SpeechResult: Sendable { public let text: String; public let seconds: Double }
public actor SpeechRecognitionService {
    private var whisper: WhisperKit?
    private var busy = false
    private var loadedFolder = ""
    public init() {}
    public var ready: Bool { whisper != nil }
    public func download(variant: String) async throws -> URL {
        guard !busy else { throw CopilotError.message("Whisper is busy") }; busy = true; defer { busy = false }
        guard ["openai_whisper-small", "openai_whisper-base", "openai_whisper-large-v3-v20240930_turbo"].contains(variant) else { throw CopilotError.message("Choose a supported multilingual Whisper model") }
        let folder = try await WhisperKit.download(variant: variant, downloadBase: LocalPaths.models)
        // Download tokenizer explicitly during this user-requested setup only.
        for name in ["tokenizer.json", "tokenizer_config.json", "config.json"] {
            let destination = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let tokenizerRepo = variant.contains("large-v3") ? "openai/whisper-large-v3-turbo" : (variant == "openai_whisper-base" ? "openai/whisper-base" : "openai/whisper-small")
                let url = URL(string: "https://huggingface.co/\(tokenizerRepo)/resolve/main/\(name)")!
                let (file, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CopilotError.message("Tokenizer download failed: \(name)") }
                try FileManager.default.moveItem(at: file, to: destination)
            }
        }
        return folder
    }
    public func load(folder: String) async throws {
        if whisper != nil && folder == loadedFolder { return }
        guard !busy else { throw CopilotError.message("Whisper is busy") }; busy = true; defer { busy = false }
        guard !folder.isEmpty else { throw CopilotError.message("Download Whisper once in Speech Recognition settings") }
        let url = URL(fileURLWithPath: folder)
        for name in ["tokenizer.json", "tokenizer_config.json", "config.json"] {
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path) else { throw CopilotError.message("Missing local \(name); download the model again. No network fallback is used.") }
        }
        if let whisper { await whisper.unloadModels() }; whisper = nil
        // Loading a local tokenizer directly avoids SDK's automatic Hub fallback on failure.
        let pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder, tokenizerFolder: url, verbose: false, prewarm: false, load: false, download: false))
        pipe.allowTokenizerDownload = false
        try await pipe.loadModels()
        whisper = pipe; loadedFolder = folder
    }
    public static func isSpeechText(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        // Whisper can label noises in otherwise voiced audio. Keep those labels
        // out of conversation text; they are not spoken questions.
        if value.hasPrefix("[") && value.hasSuffix("]") { return false }
        if value.hasPrefix("(") && value.hasSuffix(")") { return false }
        return true
    }
    public func transcribe(_ samples: [Float], language: String, vocabulary: String = "") async throws -> SpeechResult {
        guard !busy else { throw CopilotError.message("Whisper is busy") }
        guard let whisper else { throw CopilotError.message("Whisper is not loaded") }
        busy = true; defer { busy = false }
        try Task.checkCancellation()
        let start = Date()
        var options = DecodingOptions(language: language == "auto" ? nil : language, temperatureFallbackCount: 1, detectLanguage: language == "auto", skipSpecialTokens: true, suppressBlank: true, concurrentWorkerCount: 1)
        if !vocabulary.isEmpty, let tokenizer = whisper.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + String(vocabulary.prefix(1500))).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        let text = results.flatMap(\.segments).filter { $0.noSpeechProb < 0.6 && $0.avgLogprob > -1.0 && $0.compressionRatio < 2.4 && Self.isSpeechText($0.text) }.map(\.text).joined(separator: " ")
        return SpeechResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines), seconds: Date().timeIntervalSince(start))
    }
    public func transcribeFile(path: String, language: String, vocabulary: String = "") async throws -> SpeechResult {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
        return try await transcribe(samples, language: language, vocabulary: vocabulary)
    }
}
