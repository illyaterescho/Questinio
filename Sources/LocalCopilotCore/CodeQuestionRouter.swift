import Foundation

public enum CodeQuestionRouter {
    /// Only unmistakable references to code. In an interview «у вас», «у вашому проєкті», «який результат»
    /// and names like useEffect are about the candidate or the topic, not about the connected folder.
    private static let explicitCode = ["ваш код", "мій код", "коді", "в лабі", "у лабі", "лаборатор", "в файлі", "у файлі", "на екрані", "webstorm", "рядок", "рядку", "строці", "строка", "строчку", "цей код", "що робить код", "цей файл", "цьому файлі", "відкритий файл", "відкритому файлі"]
    public static func needsCode(_ question: String, previousCodeQuestion: Bool = false, interview: Bool = false) -> Bool {
        let normalized = TechnicalQuestionNormalizer.normalize(question)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized.lowercased()
        guard !value.isEmpty else { return false }
        if ProjectCodeIndex.requestedLine(value) != nil { return true }
        if normalized.range(of: #"\b[\w-]+\.(?:ts|tsx|js|jsx|py|swift|java|html|css)\b"#, options: .regularExpression) != nil { return true }
        if interview {
            if explicitCode.contains(where: value.contains) || ProjectCodeIndex.labNumber(value) != nil { return true }
            if value.range(of: #"\bin\s+(?:your|my|the|this)\s+(?:code|file|lab)\b"#, options: .regularExpression) != nil { return true }
            return previousCodeQuestion && ["а чому", "а як", "а що", "і де", "а якщо", "тоді", "тут", "там"].contains(where: value.hasPrefix)
        }
        if normalized.range(of: #"\b[a-z_][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*\b|\b[a-z_][A-Za-z0-9_]*\s*\("#, options: .regularExpression) != nil { return true }
        if ["у вас", "у вашому", "в вашому", "ваш код", "мій код", "в моєму", "в коді", "у коді", "в проєкті", "у проєкті", "в проекті", "у проекті", "в лабі", "у лабі", "в лаборатор", "у лаборатор", "в файлі", "у файлі", "на екрані", "у webstorm", "в webstorm", "де реаліз", "де визнач", "де знаход", "цей рядок", "цьому рядку", "рядок", "рядку", "строці", "строка", "строчку", "ця функція", "цю функцію", "цій функції", "цей метод", "цього методу", "ця змінна", "цю змінну", "ось тут", "ось це", "цей код", "що робить код", "що робить функц", "що робить метод", "покажи в коді", "знайди в коді", "в програмі", "у програмі", "де обчисл", "де розрах", "де вираху", "де береться", "де генер", "що виводить", "що виведе", "який результат", "скільки відхил", "що тут", "тут написано", "цей клас", "цьому класі", "цей файл", "цьому файлі", "цей цикл", "цьому циклі", "ця умова", "цей блок", "цей фрагмент", "відкритий файл", "відкритому файлі"].contains(where: value.contains) { return true }
        if ProjectCodeIndex.labNumber(value) != nil || value.range(of: #"(?:цій|цю|цієї)\s+лаб"#, options: .regularExpression) != nil { return true }
        // “де використовується…”, “покажи де…”: asks for a place in the code even when no symbol is named.
        if value.range(of: #"\bwhere\b.*\b(?:used|called|imported|defined|declared|implemented)\b|\bin\s+(?:your|my|the|this)\s+(?:code|project|file|lab)\b"#, options: .regularExpression) != nil { return true }
        if value.range(of: #"покажи\s+де|(?:^|\s)де\s.*(?:підключ|використ|юза|застосов|виклик|імпорт|написа|оголош)"#, options: .regularExpression) != nil { return true }
        if previousCodeQuestion && ["а чому", "чому", "а як", "а що", "і де", "а якщо", "а це", "тоді", "він", "вона", "воно", "це ", "тут", "там", "його", "її"].contains(where: value.hasPrefix) { return true }
        return false
    }
}

/// Questions about something drawn on screen: exact source text cannot answer them, only a screenshot can.
public enum VisualQuestionRouter {
    public static func isVisual(_ question: String) -> Bool {
        // Also «що на екрані», «що ти бачиш», «ці точки / кульки / бульбашки», «на рисунку»: the user means what they see.
        let pattern = #"(?:^|[^\p{L}])(?:на\s+екрані|бачиш|видно|зображен|точк|кульк|бульбаш|рисун|малюн|скрін|графік|діаграм|гістограм|крив(?:а|у|ої|ій|ою|і|их)(?:[^\p{L}]|$)|ліні(?:я|ї|ю|єю|й)(?:[^\p{L}]|$)|колір|кольор|вісь(?:[^\p{L}]|$)|ос(?:і|ях)(?:[^\p{L}]|$)|легенд)"#
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

/// When a screenshot may be taken and when it may leave the Mac.
/// An automatic answer is triggered by what someone else said, so it never sends the screen to the cloud.
public enum ScreenshotPolicy {
    public static func capturesForCodeQuestion(codeQuestion: Bool, allowed: Bool, cloud: Bool, automatic: Bool) -> Bool {
        codeQuestion && allowed && !(cloud && automatic)
    }
    /// «Знімки екрана» off means no capture at all: capture and OCR take ~10 s, for the cloud or a local model.
    public static func capturesForVisualQuestion(visual: Bool, allowed: Bool, cloud: Bool, automatic: Bool) -> Bool {
        visual && allowed && !(cloud && automatic)
    }
    public static func sendsImage(allowed: Bool, cloud: Bool, automatic: Bool) -> Bool {
        !cloud || (allowed && !automatic)
    }
}
