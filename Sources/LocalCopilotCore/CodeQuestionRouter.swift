import Foundation

public enum CodeQuestionRouter {
    public static func needsCode(_ question: String, previousCodeQuestion: Bool = false) -> Bool {
        let normalized = TechnicalQuestionNormalizer.normalize(question)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized.lowercased()
        guard !value.isEmpty else { return false }
        if ProjectCodeIndex.requestedLine(value) != nil { return true }
        if normalized.range(of: #"\b[a-z_][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*\b|\b[a-z_][A-Za-z0-9_]*\s*\(|\b[\w-]+\.(?:ts|tsx|js|jsx|py|swift|java|html|css)\b"#, options: .regularExpression) != nil { return true }
        if ["у вас", "у вашому", "в вашому", "ваш код", "мій код", "в моєму", "в коді", "у коді", "в проєкті", "у проєкті", "в проекті", "у проекті", "в лабі", "у лабі", "в лаборатор", "у лаборатор", "в файлі", "у файлі", "на екрані", "у webstorm", "в webstorm", "де реаліз", "де визнач", "де знаход", "цей рядок", "цьому рядку", "рядок", "рядку", "строці", "строка", "строчку", "ця функція", "цю функцію", "цій функції", "цей метод", "цього методу", "ця змінна", "цю змінну", "ось тут", "ось це", "цей код", "що робить код", "що робить функц", "що робить метод", "покажи в коді", "знайди в коді"].contains(where: value.contains) { return true }
        if value.range(of: #"(?:^|\W)(?:lab[-_ ]*\d{1,2}|лаб[а-яі]*\s*\d{1,2})(?:\W|$)"#, options: .regularExpression) != nil { return true }
        if previousCodeQuestion && ["а чому", "чому", "а як", "а що", "і де", "а якщо", "а це", "тоді", "він", "вона", "воно", "це ", "тут", "там", "його", "її"].contains(where: value.hasPrefix) { return true }
        return false
    }
}
