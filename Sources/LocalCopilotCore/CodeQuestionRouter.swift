import Foundation

public enum CodeQuestionRouter {
    public static func needsCode(_ question: String, previousCodeQuestion: Bool = false) -> Bool {
        let normalized = TechnicalQuestionNormalizer.normalize(question)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized.lowercased()
        guard !value.isEmpty else { return false }
        if ProjectCodeIndex.requestedLine(value) != nil { return true }
        if normalized.range(of: #"\b[a-z_][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*\b|\b[a-z_][A-Za-z0-9_]*\s*\(|\b[\w-]+\.(?:ts|tsx|js|jsx|py|swift|java|html|css)\b"#, options: .regularExpression) != nil { return true }
        if ["у вас", "у вашому", "в вашому", "ваш код", "мій код", "в моєму", "в коді", "у коді", "в проєкті", "у проєкті", "в проекті", "у проекті", "в лабі", "у лабі", "в лаборатор", "у лаборатор", "в файлі", "у файлі", "на екрані", "у webstorm", "в webstorm", "де реаліз", "де визнач", "де знаход", "цей рядок", "цьому рядку", "рядок", "рядку", "строці", "строка", "строчку", "ця функція", "цю функцію", "цій функції", "цей метод", "цього методу", "ця змінна", "цю змінну", "ось тут", "ось це", "цей код", "що робить код", "що робить функц", "що робить метод", "покажи в коді", "знайди в коді", "в програмі", "у програмі", "де обчисл", "де розрах", "де вираху", "де береться", "де генер", "що виводить", "що виведе", "який результат", "скільки відхил", "що тут", "тут написано", "цей клас", "цьому класі", "цей файл", "цьому файлі", "цей цикл", "цьому циклі", "ця умова", "цей блок", "цей фрагмент", "відкритий файл", "відкритому файлі"].contains(where: value.contains) { return true }
        if value.range(of: #"(?:^|\W)(?:lab[-_ ]*\d{1,2}|лаб[а-яі]*\s*\d{1,2})(?:\W|$)"#, options: .regularExpression) != nil { return true }
        if previousCodeQuestion && ["а чому", "чому", "а як", "а що", "і де", "а якщо", "а це", "тоді", "він", "вона", "воно", "це ", "тут", "там", "його", "її"].contains(where: value.hasPrefix) { return true }
        return false
    }
}

/// Questions about something drawn on screen: exact source text cannot answer them, only a screenshot can.
public enum VisualQuestionRouter {
    public static func isVisual(_ question: String) -> Bool {
        let pattern = #"(?:^|[^\p{L}])(?:графік|діаграм|гістограм|крив(?:а|у|ої|ій|ою|і|их)(?:[^\p{L}]|$)|ліні(?:я|ї|ю|єю|й)(?:[^\p{L}]|$)|колір|кольор|вісь(?:[^\p{L}]|$)|ос(?:і|ях)(?:[^\p{L}]|$)|легенд)"#
        return question.lowercased().range(of: pattern, options: .regularExpression) != nil
    }
}
/// Any JetBrains IDE counts as the editor; Toolbox is a launcher with no editor window.
public enum JetBrainsIDE {
    public static func matches(_ bundleID: String?) -> Bool {
        guard let bundleID, bundleID.hasPrefix("com.jetbrains.") else { return false }
        return !bundleID.lowercased().hasPrefix("com.jetbrains.toolbox")
    }
}
