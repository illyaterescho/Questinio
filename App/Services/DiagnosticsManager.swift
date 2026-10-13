import Foundation
import LocalCopilotCore
@MainActor final class DiagnosticsManager: ObservableObject {
    @Published var lines: [String] = []
    @Published var testing = false
    func log(_ text: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        lines.append("\(timestamp)  \(text)"); if lines.count > 160 { lines.removeFirst(lines.count - 160) }
    }
    func testOllama(_ service: OllamaService, settings: CopilotSettings) async {
        guard !testing else { return }; testing = true; defer { testing = false }
        do {
            let models = try await service.models(); log("Ollama: \(models.count) chat models; selected \(settings.model)")
            let start = Date()
            let recorder = DiagnosticTokenRecorder()
            var options = settings; options.maxTokens = 24; options.thinking = false
            try await service.chat(messages: [ChatMessage(role: "user", content: "Reply with the word Ready.")], settings: options) { packet in
                await recorder.add(packet.message?.content ?? "")
            }
            let text = await recorder.text
            log("Ollama stream completed in \(String(format: "%.2f", Date().timeIntervalSince(start))) s: \(text)")
        } catch { log("Ollama failed: \(error.localizedDescription)") }
    }
}
actor DiagnosticTokenRecorder { var text = ""; func add(_ value: String) { text += value } }
