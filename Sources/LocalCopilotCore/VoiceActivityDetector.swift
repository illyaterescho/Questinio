import Foundation

public enum AudioSource: String, Codable, Sendable { case system, microphone }
public struct AudioFrame: Sendable {
    public let samples: [Float]
    public let source: AudioSource
    public init(samples: [Float], source: AudioSource) { self.samples = samples; self.source = source }
}
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let source: AudioSource
    public let final: Bool
    public let utterance: UUID
    public let window: Int
    public let overlapsPrevious: Bool
    public init(samples: [Float], source: AudioSource, final: Bool, utterance: UUID, window: Int, overlapsPrevious: Bool) {
        self.samples = samples; self.source = source; self.final = final; self.utterance = utterance; self.window = window; self.overlapsPrevious = overlapsPrevious
    }
}
public struct VoiceActivityDetector: Sendable {
    public var threshold: Float
    public init(threshold: Float = 0.008) { self.threshold = threshold }
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
    }
    public func isSpeech(_ samples: [Float]) -> Bool { Self.rms(samples) > threshold }
}
// Bounded, source-specific utterance windows. Never mix system/mic waveforms.
public struct AudioBufferManager: Sendable {
    private var buffer: [Float] = []
    private var preRoll: [Float] = []
    private var active = false
    private var quietSamples = 0
    private var voicedSamples = 0
    private var id = UUID()
    private var window = 0
    private var overlap = false
    private var lastPreviewCount = 0
    public init() {}
    public mutating func ingest(_ frame: AudioFrame, settings: CopilotSettings) -> [AudioChunk] {
        let voiced = VoiceActivityDetector(threshold: Float(settings.vadThreshold)).isSpeech(frame.samples)
        if !active {
            if !voiced {
                preRoll.append(contentsOf: frame.samples)
                preRoll = Array(preRoll.suffix(3200))
                return []
            }
            active = true; id = UUID(); window = 0; overlap = false
            buffer = preRoll; preRoll.removeAll(); voicedSamples = 0; lastPreviewCount = 0
        }
        buffer.append(contentsOf: frame.samples)
        if voiced { quietSamples = 0; voicedSamples += frame.samples.count }
        else { quietSamples += frame.samples.count }
        let ended = quietSamples >= Int(settings.silenceSeconds * 16000)
        let full = buffer.count >= Int(settings.chunkSeconds * 16000)
        if ended || full {
            let chunk = AudioChunk(samples: buffer, source: frame.source, final: ended, utterance: id, window: window, overlapsPrevious: overlap)
            let valid = voicedSamples >= 2400 || (ended && overlap)
            if ended { reset() }
            else {
                buffer = Array(buffer.suffix(8000)); window += 1; overlap = true
                voicedSamples = 0; lastPreviewCount = buffer.count
            }
            return valid ? [chunk] : []
        }
        // Only one interim decode per window, then confirm at pause / max duration.
        if voicedSamples >= 32000 && lastPreviewCount == 0 {
            lastPreviewCount = buffer.count
            return [AudioChunk(samples: buffer, source: frame.source, final: false, utterance: id, window: window, overlapsPrevious: overlap)]
        }
        return []
    }
    public mutating func flush(source: AudioSource) -> AudioChunk? {
        defer { reset() }
        // The last full window may have consumed all fresh speech. Its overlap
        // still needs a final decode so the utterance can become a question.
        guard active, voicedSamples >= 2400 || overlap else { return nil }
        return AudioChunk(samples: buffer, source: source, final: true, utterance: id, window: window, overlapsPrevious: overlap)
    }
    public mutating func reset() { buffer.removeAll(keepingCapacity: true); preRoll.removeAll(); active = false; quietSamples = 0; voicedSamples = 0; lastPreviewCount = 0 }
}
