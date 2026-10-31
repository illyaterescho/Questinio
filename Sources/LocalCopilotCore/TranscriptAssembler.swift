import Foundation
public struct TranscriptUpdate: Sendable {
    public var confirmed: String
    public var interim: String
    public var completedUtterance: String?
    public var currentUtterance: String = ""
}
public struct TranscriptAssembler: Sendable {
    public private(set) var confirmed = ""
    public private(set) var interim = ""
    private var utterance: UUID?
    private var activeWindow = -1
    private var windowText = ""
    private var utteranceText = ""
    private var confirmedBeforeUtterance = ""
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
            confirmedBeforeUtterance = confirmed
            utterance = chunk.utterance; utteranceText = ""; windowText = ""; activeWindow = -1
        }
        if chunk.replacesUtterance {
            let provisional = (utteranceText + " " + windowText).trimmingCharacters(in: .whitespacesAndNewlines)
            // A whole-utterance decode repairs errors introduced at short
            // window boundaries. Keep the windows if that decode is blank or
            // implausibly shorter than speech already recognized.
            let useComplete = !text.isEmpty && text.split(whereSeparator: \.isWhitespace).count >= max(3, provisional.split(whereSeparator: \.isWhitespace).count / 2)
            confirmed = confirmedBeforeUtterance
            let completed = useComplete ? text : provisional
            appendConfirmed(completed)
            interim = ""; utterance = nil; utteranceText = ""; windowText = ""; activeWindow = -1
            return TranscriptUpdate(confirmed: confirmed, interim: interim, completedUtterance: completed.isEmpty ? nil : completed)
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
        return TranscriptUpdate(confirmed: confirmed, interim: interim, completedUtterance: nil, currentUtterance: (utteranceText + " " + windowText).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public mutating func discontinuity() {
        // A dropped frame or disconnected device invalidates only provisional
        // alignment. Never discard the already confirmed session transcript.
        interim = ""; utterance = nil; activeWindow = -1; windowText = ""; utteranceText = ""; confirmedBeforeUtterance = confirmed
    }
    private mutating func appendConfirmed(_ text: String) {
        guard !text.isEmpty else { return }
        confirmed = String((confirmed + " " + text).trimmingCharacters(in: .whitespaces).suffix(24000))
    }
}
