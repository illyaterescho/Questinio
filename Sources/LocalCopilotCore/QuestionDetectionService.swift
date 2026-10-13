import Foundation
public struct QuestionDetectionService: Sendable {
    private var lastQuestion = ""
    private var lastQuestionAt = Date.distantPast
    public init() {}
    public static func isQuestion(_ text: String) -> Bool {
        let value = TechnicalQuestionNormalizer.normalize(text).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }
        if value.contains("?") { return true }
        if ProjectCodeIndex.requestedLine(value) != nil,
           ["що", "шо", "чому", "як", "де", "значить", "означає", "робить", "поясни", "поясніть", "скажи", "скажіть"].contains(where: value.contains) { return true }
        let starts = ["what", "why", "how", "when", "where", "which", "who", "can you", "could you", "do you", "is there", "explain", "describe", "tell me", "write", "implement", "what about", "and if", "чим", "скільки", "навіщо", "у чому", "в чому", "для чого", "яким чином", "що", "шо", "чому", "чо", "як", "коли", "де", "якщо", "який", "яка", "які", "чи", "поясни", "поясніть", "розкажи", "розкажіть", "опиши", "напиши", "реалізуй", "покажи", "покажіть", "знайди", "скажи", "назви"]
        let clauses = value.components(separatedBy: CharacterSet(charactersIn: ".!;\n"))
        for clause in clauses {
            var lead = clause.trimmingCharacters(in: .whitespacesAndNewlines)
            for _ in 0..<3 {
                guard let filler = ["ну", "так", "окей", "добре", "слухай", "дивись", "дивіться", "тепер", "а", "і"].first(where: { lead.hasPrefix($0 + " ") || lead.hasPrefix($0 + ",") }) else { break }
                lead = String(lead.dropFirst(filler.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,\t"))
            }
            if starts.contains(where: { lead == $0 || lead.hasPrefix($0 + " ") || lead.hasPrefix($0 + ",") }) { return true }
            if ["різниця між", "відрізняється від", "відрізняються від", "означає цей", "означає ця"].contains(where: lead.contains) { return true }
            let words = lead.split(whereSeparator: { $0.isWhitespace || ",:()".contains($0) })
            if (1...5).contains(words.count), !["це ", "ми ", "я ", "вони ", "воно "].contains(where: lead.hasPrefix),
               ![" працює", " виконуються", " виконується", " повертає", " використовує", " є ", " було ", " робить"].contains(where: lead.contains) {
                let concepts = ["типізаці", "race condition", "promise", "проміс", "промис", "callback", "колбек", "async", "замикан", "closure", "рекурсі", "поліморфізм", "інкапсуляці", "react", "angular", "typescript", "javascript", "sql", "nosql"]
                if concepts.contains(where: lead.contains) { return true }
                if let expression = try? NSRegularExpression(pattern: #"\b[a-z_][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*\b|\b[a-z_][A-Za-z0-9_]*\(\)"#),
                   expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
            }
        }
        return false
    }
    // Called only for utterances completed by VAD pause, never for individual tokens.
    public mutating func completed(_ text: String, at time: Date = Date()) -> String? {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard Self.isQuestion(text) else { return nil }
        guard key != lastQuestion || time.timeIntervalSince(lastQuestionAt) >= 8 else { return nil }
        lastQuestion = key; lastQuestionAt = time
        return text
    }
}

// Repair a known typing compound, or async spellings with two independent
// programming anchors. Keep the original transcript unchanged for review.
public enum TechnicalQuestionNormalizer {
    public static func normalize(_ text: String) -> String {
        let promise = #"\b(?:promise|promises|проміс|промис|проміз|проміси|промисы)\b"#
        let callback = #"\b(?:callback|callbacks|колбек|коллбек|холлбек|калбек|колбека|колбеки)\b"#
        var result = text.replacingOccurrences(of: #"\b(?:естетично|естетична|статично)\s*[-–— ]\s*т[ие]пізація\b"#, with: "статична типізація", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bрейс\s*[-–— ]?\s*(?:кондишин|кондішин|кондишн|кондішн|кондиціон)\b"#, with: "race condition", options: [.regularExpression, .caseInsensitive])
        guard result.range(of: promise, options: [.regularExpression, .caseInsensitive]) != nil,
              result.range(of: callback, options: [.regularExpression, .caseInsensitive]) != nil else { return result }
        let asyncAwait = #"\b(?:async|асинк|асінк|айсінг|асінг)\s*[,/\s]+\s*(?:await|авейт|овейт|овейд|авейд)\b"#
        result = result.replacingOccurrences(of: asyncAwait, with: "async/await", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bас[иіе]нк(?:авит|авейт|овейт)\b"#, with: "async/await", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: promise, with: "Promise", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: callback, with: "callback", options: [.regularExpression, .caseInsensitive])
        return result
    }
}
