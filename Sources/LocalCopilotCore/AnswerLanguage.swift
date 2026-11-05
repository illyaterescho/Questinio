import Foundation

/// The language an answer is written in. English only when the question itself is English or the
/// conversation was switched to English: technical terms and code names in a Ukrainian sentence do not count.
public enum AnswerLanguage: String, Sendable {
    case ukrainian, english
    public static let englishRule = "Answer in English: the question is in English or the conversation switched to English. Keep the same rules, length and first-person form."
    private static let englishWords: Set<String> = ["what", "what's", "how", "why", "when", "where", "which", "who", "is", "are", "was", "were", "do", "does", "did", "you", "your", "the", "can", "could", "would", "should", "tell", "about", "explain", "describe", "have", "has", "walk", "me", "give", "difference", "between", "of", "to", "and", "with", "this", "that", "it", "a", "an", "in", "for", "please"]
    public static func detect(_ question: String, current: Self = .ukrainian) -> Self {
        var cyrillic = 0, english = 0
        for raw in question.split(whereSeparator: \.isWhitespace) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"«»()[]{}"))
            guard !token.isEmpty else { continue }
            if token.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { cyrillic += 1; continue }
            // useEffect, get_user, foo(), Promise.all, i18n: names from code, not English speech.
            if token.range(of: #"[a-z][A-Z]|[_().\d]"#, options: .regularExpression) != nil { continue }
            if englishWords.contains(token.lowercased().replacingOccurrences(of: "’", with: "'")) { english += 1 }
        }
        if cyrillic >= 2 { return .ukrainian }
        return english >= 1 && cyrillic == 0 ? .english : current
    }
    /// “Давай поговоримо англійською”, “let's speak English”, “back to Ukrainian”.
    public static func switchRequest(_ text: String) -> Self? {
        let value = text.lowercased()
        // A proposal to switch, not “ви говорите англійською?” or “do you speak English?”, which ask about skills.
        let verbs = #"(?:давай|давайте|поговорим|перейд|переходим|продовж|відповідай|можна|спілкуймо|поспілкуєм)"#
        let english = verbs + #"[^.!?]*англійськ|англійськ[^.!?]*(?:давай|будь ласка)|\b(?:let'?s|let us|can we|could we|shall we)\s+(?:speak|talk|switch|continue|do)[^.!?]*english|\b(?:switch|move)\s+to\s+english|\bin\s+english,?\s+please"#
        if value.range(of: english, options: .regularExpression) != nil { return .english }
        if value.range(of: verbs + #"[^.!?]*українськ|\b(?:back|switch)\s+to\s+ukrainian|\b(?:let'?s|can we)\s+(?:speak|talk|switch|continue)[^.!?]*ukrainian"#, options: .regularExpression) != nil { return .ukrainian }
        return nil
    }
}

/// Speech in Ukrainian with English parts: Whisper picks between the two only, leaning to the preferred one.
public enum BilingualSpeech {
    /// "uk+en" leans to Ukrainian, "en+uk" (after “давай англійською”) to English; any other setting is not bilingual.
    public static func preferred(_ setting: String) -> String? { setting == "uk+en" ? "uk" : setting == "en+uk" ? "en" : nil }
    /// A Ukrainian sentence full of English terms can look English: the other language must win clearly.
    /// Russian or Polish guesses for Ukrainian speech fall back to the preferred language.
    public static func choose(detected: String, logProbability: Float, preferred: String, confidence: Float = 0.8) -> String {
        let other = preferred == "uk" ? "en" : "uk"
        return detected == other && logProbability > log(confidence) ? other : preferred
    }
}
