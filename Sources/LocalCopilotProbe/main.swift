import Foundation
import LocalCopilotCore
@main struct Probe {
    static func main() async {
        do {
            let args = CommandLine.arguments
            if args.contains("--download") {
                let speech = SpeechRecognitionService()
                let variant = args.firstIndex(of: "--variant").flatMap { args.count > $0 + 1 ? args[$0+1] : nil } ?? "openai_whisper-small"
                print("Downloading \(variant)")
                let folder = try await speech.download(variant: variant)
                if !args.contains("--no-select") {
                    var settings = try SettingsManager().load(); settings.modelPath = folder.path; settings.whisperVariant = variant; try SettingsManager().save(settings)
                }
                print("MODEL_PATH=\(folder.path)")
                if !args.contains("--download-only") { try await speech.load(folder: folder.path); print("Whisper loaded") }
            } else if let index = args.firstIndex(of: "--transcribe"), args.count > index + 1 {
                let settings = try SettingsManager().load(); let speech = SpeechRecognitionService()
                let folder = args.firstIndex(of: "--model-folder").flatMap { args.count > $0 + 1 ? args[$0+1] : nil } ?? settings.modelPath
                let loadStart = Date(); try await speech.load(folder: folder)
                print("load_seconds=\(Date().timeIntervalSince(loadStart))")
                var files = [args[index+1]]
                if let also = args.firstIndex(of: "--also"), args.count > also + 1 { files.append(args[also+1]) }
                for file in files {
                    let result = try await speech.transcribeFile(path: file, language: args.firstIndex(of: "--language").flatMap { args.count > $0 + 1 ? args[$0+1] : nil } ?? settings.language, vocabulary: args.contains("--vocabulary") ? settings.speechVocabulary : "")
                    print("file=\(file)\ndecode_seconds=\(result.seconds)\ntranscript=\(result.text)")
                }
            } else {
                let service = OllamaService(); let models = try await service.models(); print("models=\(models.map(\.name))")
                var settings = try SettingsManager().load()
                if let index = args.firstIndex(of: "--model"), args.count > index + 1 { settings.model = args[index+1] }
                let start = Date(); let timer = FirstTokenTimer(start: start)
                let messages = ContextBuilder.messages(prompt: settings.systemPrompt, history: [], question: "Що таке замикання в JavaScript?", budget: 6000)
                try await service.chat(messages: messages, settings: settings) { packet in
                    if let token = packet.message?.content, !token.isEmpty { await timer.token(token) }
                }
                print("\ntotal_seconds=\(Date().timeIntervalSince(start))")
            }
        } catch { fputs("ERROR: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
actor FirstTokenTimer {
    let start: Date; var first = true
    init(start: Date) { self.start = start }
    func token(_ token: String) { if first { print("first_token_seconds=\(Date().timeIntervalSince(start))"); first = false }; print(token, terminator: "") }
}
