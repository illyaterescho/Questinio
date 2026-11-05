import Foundation
import Security

/// One chat interface for the local and the cloud model.
public protocol LLMService: Sendable {
    func chat(messages: [ChatMessage], settings: CopilotSettings, images: [String], formatJSON: Bool, onPacket: @Sendable (OllamaPacket) async -> Void) async throws
}
extension OllamaService: LLMService {}

/// The API key lives only in the macOS Keychain, never in settings.json.
public struct KeychainStore: Sendable {
    public let service: String
    public let account: String
    public init(service: String = "Questionio", account: String = "anthropic-api-key") { self.service = service; self.account = account }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    public func read() throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw CopilotError.message("Keychain: не вдалося прочитати ключ (\(status))") }
        return String(data: data, encoding: .utf8)
    }
    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CopilotError.message("Keychain: не вдалося зберегти ключ (\(status))") }
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CopilotError.message("Keychain: не вдалося видалити ключ (\(status))") }
    }
}

/// Spend for one local calendar day; a new day starts from zero.
public struct SpendLedger: Codable, Equatable, Sendable {
    public var day = ""
    public var usd = 0.0
    public var inputTokens = 0
    public var outputTokens = 0
    public init(day: String = "") { self.day = day }
    public static func dayKey(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// Claude Haiku 5.5 per million tokens: $0.10 / $0.50, or $0.50 / $2.50 for prompts over 100K tokens.
    public static func cost(input: Int, output: Int) -> Double {
        let large = input > 100_000
        return Double(input) * (large ? 0.50 : 0.10) / 1_000_000 + Double(output) * (large ? 2.50 : 0.50) / 1_000_000
    }
    public mutating func add(input: Int, output: Int, day today: String) {
        if day != today { self = SpendLedger(day: today) }
        inputTokens += input; outputTokens += output; usd += Self.cost(input: input, output: output)
    }
    public func spent(on today: String) -> Double { day == today ? usd : 0 }
}

public actor SpendTracker {
    private let url: URL
    private var ledger: SpendLedger
    public init(url: URL = LocalPaths.support.appendingPathComponent("claude-spend.json")) {
        self.url = url
        ledger = (try? JSONDecoder().decode(SpendLedger.self, from: Data(contentsOf: url))) ?? SpendLedger()
    }
    public func spentToday() -> Double { ledger.spent(on: SpendLedger.dayKey()) }
    public func record(input: Int, output: Int) {
        ledger.add(input: input, output: output, day: SpendLedger.dayKey())
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ledger) { try? data.write(to: url, options: .atomic) }
    }
}

/// Messages API streaming over plain HTTPS: Swift has no official Anthropic SDK.
public enum ClaudeRequest {
    public static let version = "2026-10-21"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static func body(messages: [ChatMessage], settings: CopilotSettings, images: [String], formatJSON: Bool) -> [String: Any] {
        var system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        if formatJSON { system += "\nВідповідай лише одним JSON-об’єктом, без Markdown і пояснень." }
        var turns: [[String: Any]] = messages.filter { $0.role != "system" }.map { ["role": $0.role, "content": $0.content] }
        if !images.isEmpty, let last = turns.lastIndex(where: { $0["role"] as? String == "user" }), let text = turns[last]["content"] as? String {
            let blocks: [[String: Any]] = images.map { ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0]] }
            turns[last]["content"] = blocks + [["type": "text", "text": text]]
        }
        // No temperature: sampling parameters return a 400 on this API version.
        var body: [String: Any] = [
            "model": settings.claudeModel, "max_tokens": settings.maxTokens > 0 ? settings.maxTokens : 8192, "stream": true, "messages": turns,
            "thinking": settings.thinking ? ["type": "adaptive", "display": "summarized"] : ["type": "disabled"],
            "output_config": ["effort": formatJSON ? "low" : "medium"]
        ]
        if !system.isEmpty { body["system"] = system }
        return body
    }
    public static func failure(status: Int, body: String) -> String {
        let detail = ((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
        switch status {
        case 401, 403: return "Claude: ключ не прийнято. Перевірте його в панелі «Модель AI»."
        case 402: return "Claude: на рахунку Anthropic немає коштів."
        case 429: return "Claude: перевищено ліміт запитів. Спробуйте за хвилину."
        case 529: return "Claude: сервіс перевантажений. Спробуйте ще раз."
        default: return "Claude HTTP \(status)" + (detail.isEmpty ? "" : ": " + detail)
        }
    }
}

/// Folds Server-Sent Events into the packets the answer pipeline already reads.
public struct ClaudeStreamParser: Sendable {
    public private(set) var inputTokens = 0
    public private(set) var outputTokens: Int?
    public private(set) var characters = 0
    public private(set) var stopReason: String?
    public private(set) var finished = false
    public init() {}
    public mutating func parse(_ line: String) throws -> OllamaPacket? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any], let type = event["type"] as? String else { return nil }
        switch type {
        case "message_start":
            let usage = (event["message"] as? [String: Any])?["usage"] as? [String: Any]
            for key in ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"] { inputTokens += usage?[key] as? Int ?? 0 }
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any]
            if delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String {
                characters += text.count; return OllamaPacket(content: text)
            }
            if delta?["type"] as? String == "thinking_delta", let text = delta?["thinking"] as? String { return OllamaPacket(thinking: text) }
        case "message_delta":
            stopReason = (event["delta"] as? [String: Any])?["stop_reason"] as? String
            outputTokens = (event["usage"] as? [String: Any])?["output_tokens"] as? Int ?? outputTokens
        case "message_stop":
            finished = true
            if stopReason == "refusal" { throw CopilotError.message("Claude відмовився відповідати на цей запит.") }
            return OllamaPacket(done: true, doneReason: stopReason == "max_tokens" ? "length" : stopReason)
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "невідома помилка"
            throw CopilotError.message("Claude: " + message)
        default: break
        }
        return nil
    }
    /// A cancelled stream never reports output usage, so estimate it from the text received.
    public var billableOutput: Int { outputTokens ?? characters / 3 }
}

public actor ClaudeService: LLMService {
    public nonisolated let keychain: KeychainStore
    public nonisolated let spend: SpendTracker
    private let session: URLSession
    /// Read once per launch: the Keychain lookup is slow, and after a rebuild macOS may stop to ask for access.
    private var cachedKey: String?
    public func forgetKey() { cachedKey = nil }
    public init(keychain: KeychainStore = KeychainStore(), spend: SpendTracker = SpendTracker()) {
        self.keychain = keychain; self.spend = spend
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }
    public func chat(messages: [ChatMessage], settings: CopilotSettings, images: [String], formatJSON: Bool, onPacket: @Sendable (OllamaPacket) async -> Void) async throws {
        if cachedKey == nil { cachedKey = try keychain.read() }
        guard let key = cachedKey, !key.isEmpty else { throw CopilotError.message("Ключ Claude не задано. Вставте його в панелі «Модель AI».") }
        guard await spend.spentToday() < settings.claudeDailyLimitUSD else {
            throw CopilotError.message(String(format: "Claude: денний ліміт $%.2f вичерпано. Підніміть його в панелі «Модель AI» або перемкніться на Ollama.", settings.claudeDailyLimitUSD))
        }
        var request = URLRequest(url: ClaudeRequest.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeRequest.version, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: ClaudeRequest.body(messages: messages, settings: settings, images: images, formatJSON: formatJSON))
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = ""
            for try await line in bytes.lines where body.utf8.count < 64_000 { body += line }
            throw CopilotError.message(ClaudeRequest.failure(status: status, body: body))
        }
        var parser = ClaudeStreamParser()
        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                if let packet = try parser.parse(line) { await onPacket(packet) }
                if parser.finished { break }
            }
        } catch {
            await spend.record(input: parser.inputTokens, output: parser.billableOutput)
            throw error
        }
        await spend.record(input: parser.inputTokens, output: parser.billableOutput)
        guard parser.finished else { throw CopilotError.message("Claude перервав відповідь до завершення") }
    }
}
