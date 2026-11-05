import Foundation

/// Loaded study materials (lab write-ups, explanations, notes) split into passages; a question gets
/// only the passages that share its words, so a long document does not go out with every answer.
public struct DocumentIndex: Sendable {
    public struct Passage: Sendable, Equatable {
        public let file: String
        public let text: String
        let terms: Set<String>
    }
    public private(set) var passages: [Passage] = []
    private var documentFrequency: [String: Int] = [:]
    public init(documents: [(name: String, text: String)] = []) {
        for document in documents {
            for text in Self.chunks(document.text) { passages.append(Passage(file: document.name, text: text, terms: Self.terms(text))) }
        }
        for passage in passages { for term in passage.terms { documentFrequency[term, default: 0] += 1 } }
    }
    public var isEmpty: Bool { passages.isEmpty }
    /// Paragraphs joined up to ~900 characters; a longer paragraph is cut at sentence ends.
    static func chunks(_ text: String, size: Int = 900) -> [String] {
        var result: [String] = []; var current = ""
        func flush() { let value = current.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { result.append(value) }; current = "" }
        for paragraph in text.components(separatedBy: "\n") {
            let paragraph = paragraph.trimmingCharacters(in: .whitespaces)
            guard !paragraph.isEmpty else { continue }
            if current.count + paragraph.count + 1 > size { flush() }
            if paragraph.count > size {
                var rest = Substring(paragraph)
                while rest.count > size {
                    let window = rest.prefix(size)
                    let cut = window.lastIndex(where: { ".!?;".contains($0) }).map { rest.index(after: $0) } ?? window.endIndex
                    result.append(String(rest[..<cut]).trimmingCharacters(in: .whitespaces)); rest = rest[cut...]
                }
                current = String(rest)
            } else { current += (current.isEmpty ? "" : "\n") + paragraph }
        }
        flush()
        return result
    }
    private static let stopWords: Set<String> = ["що", "як", "це", "цей", "ця", "ці", "той", "для", "або", "але", "при", "про", "від", "над", "під", "між", "яка", "який", "які", "якщо", "чому", "коли", "тут", "там", "так", "теж", "ще", "вже", "був", "була", "було", "бути", "його", "її", "їх", "ми", "ви", "він", "вона", "воно", "вони", "мені", "тобі", "нам", "вам", "чи", "та", "і", "й", "а", "в", "у", "з", "із", "на", "до", "по", "не", "ні", "the", "and", "for", "with", "what", "how", "why", "this", "that", "from", "are", "was", "is", "you", "your"]
    private static let scripts: [Character: Character] = Dictionary(uniqueKeysWithValues: zip("⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉", "01234567890123456789"))
    /// Lower-cased words cut to a six-letter stem so «дисперсія» and «дисперсії» match. Short words count only
    /// as notation with a digit (R², X1, H₀ written as r2, x1, h0), which formulas in materials are full of.
    static func terms(_ text: String) -> Set<String> {
        var result = Set<String>()
        // Letter subscripts are indices: Rₖ² is searched as R².
        let text = String(text.lowercased().filter { !"ₐₑₒₓₕₖₗₘₙₚₛₜᵢⱼ".contains($0) }.map { scripts[$0] ?? $0 })
        for word in text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let word = String(word)
            guard word.count >= 3 || (word.count == 2 && word.contains(where: \.isNumber) && word.contains(where: \.isLetter)) else { continue }
            guard !stopWords.contains(word) else { continue }
            result.insert(String(word.prefix(6)))
        }
        return result
    }
    /// Passages for one question, best first, within `limit` characters. Small materials go whole.
    public func context(for query: String, limit: Int = 3000) -> String {
        guard !passages.isEmpty else { return "" }
        if passages.reduce(0, { $0 + $1.text.count + $1.file.count + 4 }) <= limit { return render(passages) }
        let wanted = Self.terms(query)
        guard !wanted.isEmpty else { return "" }
        let total = Double(passages.count)
        let scored = passages.enumerated().compactMap { index, passage -> (Int, Double)? in
            let score = wanted.intersection(passage.terms).reduce(0.0) { $0 + log(1 + total / Double(documentFrequency[$1] ?? 1)) }
            return score > 0 ? (index, score) : nil
        }.sorted { $0.1 > $1.1 }
        var chosen: [Int] = []; var used = 0
        for (index, _) in scored {
            let size = passages[index].text.count + passages[index].file.count + 4
            if used + size > limit { if chosen.isEmpty { continue } else { break } }
            chosen.append(index); used += size
        }
        // In document order, so a derivation reads top to bottom.
        return render(chosen.sorted().map { passages[$0] })
    }
    private func render(_ passages: [Passage]) -> String {
        passages.map { "[\($0.file)]\n\($0.text)" }.joined(separator: "\n\n")
    }
}

/// Text of a .docx, including Word equations written out linearly: (a)/(b), x^(2), √(x).
public enum DocxText {
    public static func text(fromDocx url: URL) throws -> String {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]
        process.standardOutput = output; process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw CopilotError.message("Не вдалося прочитати \(url.lastPathComponent) як Word-документ") }
        return text(fromDocumentXML: data)
    }
    public static func text(fromDocumentXML data: Data) -> String {
        let reader = Reader(); let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
        return reader.output
            .replacingOccurrences(of: #"\s*\|\s*\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*\n[ \t]*\n\s*"#, with: "\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private final class Reader: NSObject, XMLParserDelegate {
        var output = ""
        private var inText = false
        private var naryPending = false
        private var cellDepth = 0
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "w:t", "m:t": inText = true
            case "w:tc": cellDepth += 1
            case "w:tab": output += "\t"
            case "w:br", "w:cr": output += "\n"
            case "m:num", "m:d", "m:den": output += "("
            case "m:sup": output += "^("
            case "m:sub": output += "_("
            case "m:rad": output += "√("
            case "m:nary": naryPending = true
            case "m:chr": if naryPending, let symbol = attributes["m:val"] { output += symbol; naryPending = false }
            case "m:e": if naryPending { output += "∫"; naryPending = false }
            default: break
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:t", "m:t": inText = false
            // A table row is one line: «X1 | 4,02267 | -12,12289».
            case "w:p": output += cellDepth > 0 ? " " : "\n"
            case "w:tr": output += "\n"
            case "w:tc": cellDepth -= 1; output += " | "
            case "m:num": output += ")/"
            case "m:den", "m:d", "m:sup", "m:sub", "m:rad": output += ")"
            case "m:oMath": output += " "
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { output += string } }
    }
}
