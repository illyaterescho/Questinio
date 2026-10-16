import Foundation

/// Owned by the speech actor. Only overflow audio is spilled, never from a
/// real-time capture callback. Files are private and deleted after decoding.
public final class QueuedAudioChunk: @unchecked Sendable {
    public let metadata: AudioChunk
    public let sampleCount: Int
    private var resident: [Float]?
    private var fallback: [Float]?
    private var audioURL: URL?
    private var fallbackURL: URL?
    public var residentSampleCount: Int { (resident?.count ?? 0) + (fallback?.count ?? 0) }
    public var spooledBytes: Int { audioURL == nil ? 0 : (sampleCount + (fallbackCount)) * MemoryLayout<Float>.size }
    private let fallbackCount: Int
    public var attempts = 0
    public static func cleanupStaleDirectories(in root: URL = FileManager.default.temporaryDirectory, before cutoff: Date = Date().addingTimeInterval(-86400)) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else { return }
        for file in files where file.lastPathComponent.hasPrefix("questionio-speech-") {
            guard let values = try? file.resourceValues(forKeys: keys), values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
    public init(_ chunk: AudioChunk) {
        sampleCount = chunk.samples.count; fallbackCount = chunk.fallbackSamples?.count ?? 0
        resident = chunk.samples; fallback = chunk.fallbackSamples
        metadata = AudioChunk(samples: [], source: chunk.source, final: chunk.final, utterance: chunk.utterance, window: chunk.window,
                              overlapsPrevious: chunk.overlapsPrevious, replacesUtterance: chunk.replacesUtterance,
                              isPreview: chunk.isPreview, capturedAt: chunk.capturedAt)
    }
    public func spill(to directory: URL) throws {
        guard let resident else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let audio = directory.appendingPathComponent(UUID().uuidString + ".pcm")
        let backup = directory.appendingPathComponent(UUID().uuidString + ".pcm")
        do {
            try Self.write(resident, to: audio)
            if let fallback { try Self.write(fallback, to: backup) }
        } catch {
            try? FileManager.default.removeItem(at: audio); try? FileManager.default.removeItem(at: backup)
            throw error
        }
        audioURL = audio; fallbackURL = fallback == nil ? nil : backup
        self.resident = nil; fallback = nil
    }
    public func load() throws -> AudioChunk {
        let samples = try resident ?? Self.read(audioURL, count: sampleCount)
        let backup = try fallback ?? (fallbackURL == nil ? nil : Self.read(fallbackURL, count: fallbackCount))
        return AudioChunk(samples: samples, source: metadata.source, final: metadata.final, utterance: metadata.utterance, window: metadata.window,
                          overlapsPrevious: metadata.overlapsPrevious, replacesUtterance: metadata.replacesUtterance,
                          fallbackSamples: backup, isPreview: metadata.isPreview, capturedAt: metadata.capturedAt)
    }
    private static func write(_ samples: [Float], to url: URL) throws {
        let data = samples.withUnsafeBytes { Data($0) }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func read(_ url: URL?, count: Int) throws -> [Float] {
        guard let url else { throw CopilotError.message("Missing queued audio") }
        let data = try Data(contentsOf: url)
        guard data.count == count * MemoryLayout<Float>.size else { throw CopilotError.message("Queued audio is truncated") }
        var samples = [Float](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return samples
    }
    deinit {
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        if let fallbackURL { try? FileManager.default.removeItem(at: fallbackURL) }
    }
}
