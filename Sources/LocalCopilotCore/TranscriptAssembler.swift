import Foundation
public struct TranscriptUpdate: Sendable {
    public var confirmed: String
    public var interim: String
    public var completedUtterance: String?
}
public struct TranscriptAssembler: Sendable {
    public private(set) var confirmed = ""
    public private(set) var interim = ""
    private var utterance: UUID?
    private var activeWindow = -1
    private var windowText = ""
    private var utteranceText = ""
    public init() {}
    private static func normalized(_ word: String) -> String { word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
    public static func removeOverlap(previous: String, next: String) -> String {
        let a = previous.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = next.split(whereSeparator: \.isWhitespace).map(String.init)
        let maximum = min(24, a.count, b.count)
        if maximum > 0 {
            for count in stride(from: maximum, through: 1, by: -1) {
                if a.suffix(count).map(normalized) == b.prefix(count).map(normalized) { return b.dropFirst(count).joined(separator: " ") }
            }
        }
        return next
    }
    public mutating func accept(_ text: String, chunk: AudioChunk) -> TranscriptUpdate {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if utterance != chunk.utterance {
            if !windowText.isEmpty { appendConfirmed(windowText) }
            utterance = chunk.utterance; utteranceText = ""; windowText = ""; activeWindow = -1
        }
        if chunk.window != activeWindow {
            if !windowText.isEmpty {
                appendConfirmed(windowText)
                utteranceText = (utteranceText + " " + windowText).trimmingCharacters(in: .whitespaces)
            }
            activeWindow = chunk.window; windowText = ""
        }
        windowText = chunk.overlapsPrevious ? Self.removeOverlap(previous: utteranceText, next: text) : text
        interim = windowText
        if chunk.final {
            appendConfirmed(windowText)
            let completed = (utteranceText + " " + windowText).trimmingCharacters(in: .whitespaces)
            windowText = ""; interim = ""; utterance = nil; utteranceText = ""
            return TranscriptUpdate(confirmed: confirmed, interim: interim, completedUtterance: completed.isEmpty ? nil : completed)
        }
        return TranscriptUpdate(confirmed: confirmed, interim: interim, completedUtterance: nil)
    }
    public mutating func discontinuity() {
        // A dropped frame or disconnected device invalidates only provisional
        // alignment. Never discard the already confirmed session transcript.
        interim = ""; utterance = nil; activeWindow = -1; windowText = ""; utteranceText = ""
    }
    private mutating func appendConfirmed(_ text: String) {
        guard !text.isEmpty else { return }
        confirmed = String((confirmed + " " + text).trimmingCharacters(in: .whitespaces).suffix(24000))
    }
}
