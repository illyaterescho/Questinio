import Foundation

public struct DialogueRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let source: String
    public let text: String
    public let kind: String
    public init(id: UUID = UUID(), date: Date = Date(), source: String, text: String, kind: String = "speech") {
        self.id = id; self.date = date; self.source = source; self.text = text; self.kind = kind
    }
}

/// Append-only final text; no microphone/system waveform is written here.
/// An incomplete last line after a crash is recoverable, a corrupt middle line
/// is surfaced rather than silently skipping part of the conversation.
public actor SessionJournal {
    public let directory: URL
    public init(directory: URL = LocalPaths.support.appendingPathComponent("Sessions")) { self.directory = directory }
    public func url(session: UUID) -> URL { directory.appendingPathComponent(session.uuidString + ".jsonl") }
    public func append(_ record: DialogueRecord, session: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = url(session: session)
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        var data = try JSONEncoder().encode(record); data.append(0x0a)
        let handle = try FileHandle(forUpdating: file); defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1)?.last != 0x0a {
                let committed = try Data(contentsOf: file).lastIndex(of: 0x0a).map { UInt64($0 + 1) } ?? 0
                try handle.truncate(atOffset: committed)
            }
        }
        try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize()
    }
    public func records(session: UUID) throws -> [DialogueRecord] {
        let file = url(session: session)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        var lines = data.split(separator: 0x0a, omittingEmptySubsequences: false)
        if data.last != 0x0a { lines.removeLast() } // uncommitted trailing record
        return try lines.filter { !$0.isEmpty }.map { try JSONDecoder().decode(DialogueRecord.self, from: Data($0)) }
    }
    public func latest() throws -> UUID? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        return files.filter { $0.pathExtension == "jsonl" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .first.flatMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }
    public func relevant(question: String, session: UUID, before cutoff: Date = .distantFuture, budget: Int = 2200) throws -> String {
        let query = Self.tokens(question)
        guard !query.isEmpty else { return "" }
        let speech = try records(session: session).filter { ($0.kind == "speech" || $0.kind == "manual") && $0.date <= cutoff }
        var scored: [(index: Int, record: DialogueRecord, score: Int)] = []
        for (index, item) in speech.enumerated() {
            let score = Self.tokens(item.text).intersection(query).count
            if score > 0 { scored.append((index, item, score)) }
        }
        scored.sort { a, b in a.score == b.score ? a.index > b.index : a.score > b.score }
        let ranked = scored.prefix(4).sorted { $0.index < $1.index }
        let blocks = ranked.map { item in "[\(item.record.date.formatted(date: .omitted, time: .standard)) · \(item.record.source)] \(item.record.text)" }
        return String(blocks.joined(separator: "\n").prefix(budget))
    }
    private static func tokens(_ text: String) -> Set<String> {
        let stop: Set<String> = ["чому", "таке", "поясни", "будь", "ласка", "цього", "цьому", "нашій", "вашій", "було", "який", "означає"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { ($0.count >= 4 || Int($0) != nil) && !stop.contains($0) }.map { String($0.prefix(6)) })
    }
    public static func export(_ records: [DialogueRecord]) -> String {
        records.map { "[\($0.date.formatted(date: .omitted, time: .standard)) · \($0.source) · \($0.kind)]\n\($0.text)" }.joined(separator: "\n\n")
    }
    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "jsonl" {
            try FileManager.default.removeItem(at: file)
        }
    }
}
