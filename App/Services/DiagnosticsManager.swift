import Foundation
import LocalCopilotCore
@MainActor final class DiagnosticsManager: ObservableObject {
    @Published var lines: [String] = []
    @Published var testing = false
    /// `onDisk: false` for lines that quote what was said.
    func log(_ text: String, onDisk: Bool = true) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        lines.append("\(timestamp)  \(text)"); if lines.count > 160 { lines.removeFirst(lines.count - 160) }
        if onDisk { Self.append("\(Date().ISO8601Format())  \(text)\n") }
    }
    /// Also kept on disk (no questions or answers, only events and timings) so a slow answer can be looked at later.
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Questionio/diagnostics.log")
    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 1_000_000 { try? manager.removeItem(at: file) }
        if !manager.fileExists(atPath: file.path) { manager.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8))
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
