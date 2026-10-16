import Foundation

public enum SpeechVocabulary {
    public static let profiles = ["General", "Mathematics", "JavaScript", "Python", "SQL"]
    public static func text(profile: String, custom: String) -> String {
        let terms: String
        switch profile {
        case "Mathematics": terms = LabDefenseProfile.vocabulary
        case "JavaScript": terms = "JavaScript, TypeScript, Promise, async/await, callback, closure, event loop, React, Node.js, null, undefined, NaN, race condition, рейс кондишн, уникати, статична типізація, динамічна типізація."
        case "Python": terms = "Python, asyncio, coroutine, generator, decorator, GIL, list, tuple, dictionary, type hints, статична типізація, динамічна типізація."
        case "SQL": terms = "SQL, PostgreSQL, MySQL, SELECT, JOIN, GROUP BY, HAVING, index, transaction, ACID, isolation, deadlock, індекс, транзакція."
        default: terms = "race condition, рейс кондишн, уникати, Promise, async/await, callback, JavaScript, TypeScript, статична типізація."
        }
        return String((terms + " " + custom).trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
    }
}
public enum QuestionContextRouter {
    public static func isSelfContained(_ question: String) -> Bool {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ProjectCodeIndex.namedSymbol(question) != nil { return true }
        let references = [" цей ", " ця ", " це ", " цього ", " цієї ", " тут", " там", " він ", " вона ", " воно ", " вони ", " раніше", " попередн", " той ", " такий ", " зараз"]
        if references.contains(where: { (" " + normalized + " ").contains($0) }) { return false }
        return ["що таке ", "чим відрізня", "поясни ", "яка різниця між ", "як працює "].contains { normalized.hasPrefix($0) }
    }
}
public struct SessionContext: Sendable {
    public struct Turn: Sendable, Equatable {
        public let speaker: String
        public let text: String
        public var rendered: String { "[\(speaker)] \(text)" }
    }
    public private(set) var turns: [Turn] = []
    public private(set) var archived = ""
    public var summary = ""
    public init() {}
    public mutating func append(speaker: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        turns.append(Turn(speaker: speaker, text: String(text.prefix(12000))))
        while turns.count > 60 || turns.reduce(0, { $0 + $1.text.count }) > 24000 {
            archived += turns.removeFirst().rendered + "\n"
        }
        archived = String(archived.suffix(60000))
    }
    public var recent: String { turns.map(\.rendered).joined(separator: "\n") }
    public mutating func consumeArchive(_ snapshot: String, summary: String) {
        guard archived.hasPrefix(snapshot) else { return }
        self.summary = String(summary.prefix(5000))
        archived.removeFirst(snapshot.count)
    }
    public func messages(prompt: String, history: [ChatMessage], question: String, code: String, topic: String, budget: Int, includeConversation: Bool = true) -> [ChatMessage] {
        let budget = max(1024, budget)
        let system = String(prompt.prefix(min(2000, budget / 4)))
        let question = String(question.suffix(min(8000, budget / 4)))
        var left = budget - system.count - question.count - 100
        var blocks: [String] = []
        func add(_ label: String, _ text: String, maximum: Int, tail: Bool = false) {
            guard !text.isEmpty, left > label.count + 4 else { return }
            let count = min(maximum, left - label.count - 4)
            let value = tail ? String(text.suffix(count)) : String(text.prefix(count))
            blocks.append(label + "\n" + value); left -= label.count + value.count + 2
        }
        if includeConversation { add("Тема / умови розмови (дані):", topic, maximum: 1200) }
        add("Показаний код / OCR екрана (дані):", code, maximum: max(0, left * 70 / 100))
        if includeConversation {
            add("Пам’ять попередньої розмови (дані):", summary, maximum: min(4000, left / 2))
            add("Репліки розмови (дані):", String(archived.suffix(2000)) + "\n" + recent, maximum: max(0, left * 70 / 100), tail: true)
        }
        var kept: [ChatMessage] = []
        if includeConversation && recent.isEmpty {
            var index = history.count - 2
            while index >= 0 {
                let pair = Array(history[index...index + 1]); let size = pair.reduce(0) { $0 + $1.content.count }
                guard pair[0].role == "user", pair[1].role == "assistant", size <= left else { break }
                kept.insert(contentsOf: pair, at: 0); left -= size; index -= 2
            }
        }
        let user = blocks.joined(separator: "\n\n") + "\n\nПоточне питання (відповідай саме на нього):\n" + question
        return [ChatMessage(role: "system", content: system)] + kept + [ChatMessage(role: "user", content: user)]
    }
}

public struct QuestionInbox: Sendable {
    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        public let text: String
        public let source: String
        public let date: Date
        public let context: SessionContext
    }
    public private(set) var entries: [Entry] = []
    public init() {}
    public mutating func append(_ text: String, source: String, context: SessionContext, at date: Date = Date()) {
        guard QuestionDetectionService.isQuestion(text) else { return }
        let normalized = TechnicalQuestionNormalizer.normalize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = entries.last, last.source == source, last.text == normalized, date.timeIntervalSince(last.date) < 8 { return }
        entries.append(Entry(text: normalized, source: source, date: date, context: context))
        if entries.count > 50 { entries.removeFirst(entries.count - 50) }
    }
}
