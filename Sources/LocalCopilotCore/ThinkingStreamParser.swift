import Foundation
// Some local templates place thinking tags inside content instead of message.thinking.
// Preserve tag fragments across packets and keep them out of the visible answer.
public struct ThinkingStreamParser: Sendable {
    public private(set) var answer = ""
    public private(set) var thinking = ""
    private var pending = ""
    private var insideThinking = false
    private let tags = ["<think>", "</think>"]
    public init() {}
    public mutating func append(_ token: String) {
        pending += token
        while !pending.isEmpty {
            let ranges = tags.compactMap { tag in pending.range(of: tag).map { (tag, $0) } }
            if let (tag, range) = ranges.min(by: { $0.1.lowerBound < $1.1.lowerBound }) {
                emit(String(pending[..<range.lowerBound]))
                pending = String(pending[range.upperBound...])
                if tag == "<think>" { insideThinking = true }
                else {
                    // A prefilled assistant may produce only a closing tag.
                    if !insideThinking { thinking += answer; answer = "" }
                    insideThinking = false
                }
                continue
            }
            var held = 0
            for count in 1...min(8, pending.count) {
                let suffix = String(pending.suffix(count))
                if tags.contains(where: { $0.hasPrefix(suffix) }) { held = count }
            }
            emit(String(pending.dropLast(held))); pending = String(pending.suffix(held)); break
        }
    }
    public mutating func finish() { emit(pending); pending = "" }
    private mutating func emit(_ text: String) { if insideThinking { thinking += text } else { answer += text } }
}
