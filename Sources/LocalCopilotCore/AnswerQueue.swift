import Foundation

/// Questions waiting for an answer, oldest first. One answer runs at a time, so a question asked meanwhile waits its turn.
public struct AnswerQueue: Sendable {
    public struct Item: Sendable {
        public let text: String
        public let context: SessionContext?
        public let before: Date
        public let entryID: UUID?
        public let revision: Int
        public let automatic: Bool
        public init(text: String, context: SessionContext?, before: Date, entryID: UUID? = nil, revision: Int = 0, automatic: Bool = false) {
            self.text = text; self.context = context; self.before = before; self.entryID = entryID; self.revision = revision; self.automatic = automatic
        }
    }
    public private(set) var items: [Item] = []
    public init() {}
    /// A newer revision of a waiting question keeps its place; the same text is not asked twice.
    public mutating func add(_ item: Item) {
        if let id = item.entryID, let index = items.firstIndex(where: { $0.entryID == id }) { items[index] = item; return }
        guard !items.contains(where: { $0.text == item.text }) else { return }
        items.append(item)
    }
    /// Skips an automatic question the speaker has since changed or dropped. A question the user chose is always answered.
    public mutating func next(isCurrent: (UUID, Int) -> Bool) -> Item? {
        while !items.isEmpty {
            let item = items.removeFirst()
            if item.automatic, let id = item.entryID, !isCurrent(id, item.revision) { continue }
            return item
        }
        return nil
    }
    public mutating func removeAll() { items.removeAll() }
}

/// Answers of this session, so the next question does not wipe the previous answer off the screen.
public struct AnswerLog: Sendable {
    public struct Turn: Sendable, Equatable {
        public let question: String
        public let answer: String
        public let interrupted: Bool
    }
    public private(set) var turns: [Turn] = []
    /// The turn being looked at; nil follows the live answer.
    public private(set) var shown: Int?
    public init() {}
    public var shownTurn: Turn? { shown.map { turns[$0] } }
    public mutating func add(question: String, answer: String, interrupted: Bool = false) {
        turns.append(Turn(question: question, answer: answer, interrupted: interrupted))
        if turns.count > 50 {
            turns.removeFirst()
            shown = shown.map { max(0, $0 - 1) }
        }
    }
    /// Pages are the logged turns, plus the live answer when it is not logged yet.
    public func pageCount(liveIsLogged: Bool) -> Int { turns.count + (liveIsLogged ? 0 : 1) }
    public func page(liveIsLogged: Bool) -> Int { shown ?? pageCount(liveIsLogged: liveIsLogged) - 1 }
    public mutating func move(by delta: Int, liveIsLogged: Bool) {
        let target = page(liveIsLogged: liveIsLogged) + delta
        let last = pageCount(liveIsLogged: liveIsLogged) - 1
        guard target >= 0, target <= last else { return }
        shown = target == last ? nil : target
    }
    public mutating func showLive() { shown = nil }
}
