import Foundation
public struct ChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}
public struct OllamaModel: Decodable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let size: Int64
    public let capabilities: [String]?
}
public struct OllamaPacket: Decodable, Sendable {
    public struct Message: Decodable, Sendable { public let content: String?; public let thinking: String? }
    public let message: Message?
    public let done: Bool?
    public let error: String?
    public let done_reason: String?
    public let load_duration: Int64?
    public let prompt_eval_duration: Int64?
    public let eval_duration: Int64?
    public let prompt_eval_count: Int?
    public let eval_count: Int?
    public static func parse(_ line: String) throws -> OllamaPacket {
        guard line.utf8.count <= 1_000_000 else { throw CopilotError.message("Ollama packet exceeds limit") }
        let packet = try JSONDecoder().decode(Self.self, from: Data(line.utf8))
        if let error = packet.error { throw CopilotError.message(error) }
        return packet
    }
}
public enum ContextBuilder {
    public static func messages(prompt: String, history: [ChatMessage], question: String, budget: Int) -> [ChatMessage] {
        let budget = max(512, budget)
        let question = String(question.suffix(budget / 2))
        let prompt = String(prompt.prefix(budget / 3))
        var remaining = budget - question.count - prompt.count
        var kept: [ChatMessage] = []
        // Keep complete user/assistant pairs; never start history with an orphan answer.
        var index = history.count - 2
        while index >= 0 {
            let pair = Array(history[index...index + 1])
            let size = pair.reduce(0) { $0 + $1.content.count }
            guard pair[0].role == "user", pair[1].role == "assistant", size <= remaining else { break }
            kept.insert(contentsOf: pair, at: 0); remaining -= size; index -= 2
        }
        return [ChatMessage(role: "system", content: prompt)] + kept + [ChatMessage(role: "user", content: question)]
    }
}
public actor OllamaService {
    private static let keepAlive = "2h"
    private var cachedCapabilities: [String: [String]] = [:]
    private let session: URLSession
    private let base = URL(string: "http://127.0.0.1:11434")!
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 86400
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
    }
    public func models() async throws -> [OllamaModel] {
        let (data, response) = try await session.data(from: base.appendingPathComponent("api/tags"))
        try Self.check(response)
        struct Response: Decodable { let models: [OllamaModel] }
        return try JSONDecoder().decode(Response.self, from: data).models.filter { $0.capabilities?.contains("embedding") != true || $0.capabilities?.contains("completion") == true }
    }
    private func capabilities(model: String) async throws -> [String] {
        if let cached = cachedCapabilities[model] { return cached }
        var request = URLRequest(url: base.appendingPathComponent("api/show"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        let (data, response) = try await session.data(for: request); try Self.check(response)
        struct Info: Decodable { let capabilities: [String]? }
        let result = try JSONDecoder().decode(Info.self, from: data).capabilities ?? []
        cachedCapabilities[model] = result; return result
    }
    public func supportsThinking(model: String) async throws -> Bool { try await capabilities(model: model).contains("thinking") }
    public func supportsVision(model: String) async throws -> Bool { try await capabilities(model: model).contains("vision") }
    public func warm(model: String, contextTokens: Int) async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": "", "stream": false, "keep_alive": Self.keepAlive, "options": ["num_ctx": contextTokens]] as [String: Any])
        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }
    public static func requestMessages(_ messages: [ChatMessage], model: String, thinking: Bool, supported: Bool) -> [ChatMessage] {
        // Some installed Qwen3 templates always open <think> despite think=false.
        // A completed empty thinking prefix prevents that template from opening it.
        guard supported, !thinking, model.lowercased().hasPrefix("qwen3:") else { return messages }
        var result = messages
        if let index = result.lastIndex(where: { $0.role == "user" }) {
            result[index] = ChatMessage(role: "user", content: result[index].content + "\n/no_think")
        }
        return result + [ChatMessage(role: "assistant", content: "<think>\n</think>\n\n")]
    }
    public func chat(messages: [ChatMessage], settings: CopilotSettings, images: [String] = [], formatJSON: Bool = false, onPacket: @Sendable (OllamaPacket) async -> Void) async throws {
        let thinkingSupported = try await supportsThinking(model: settings.model)
        let requestMessages = Self.requestMessages(messages, model: settings.model, thinking: settings.thinking, supported: thinkingSupported)
        var serializedMessages: [[String: Any]] = requestMessages.map { ["role": $0.role, "content": $0.content] }
        if !images.isEmpty, let index = requestMessages.lastIndex(where: { $0.role == "user" }) { serializedMessages[index]["images"] = images }
        var body: [String: Any] = ["model": settings.model, "messages": serializedMessages, "stream": true, "keep_alive": Self.keepAlive, "options": ["temperature": settings.temperature, "num_predict": settings.maxTokens > 0 ? settings.maxTokens : -1, "num_ctx": settings.contextTokens]]
        if thinkingSupported { body["think"] = settings.thinking }
        if formatJSON { body["format"] = "json" }
        var request = URLRequest(url: base.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await session.bytes(for: request)
        try Self.check(response)
        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty { continue }
            let packet = try OllamaPacket.parse(line)
            await onPacket(packet)
            if packet.done == true { completed = true; break }
        }
        guard completed else { throw CopilotError.message("Ollama interrupted the stream before completion") }
    }
    public static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CopilotError.message("Ollama HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). Check that the selected model is installed and Ollama is running.")
        }
    }
}
