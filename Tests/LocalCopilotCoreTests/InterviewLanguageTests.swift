import XCTest
@testable import LocalCopilotCore

final class InterviewLanguageTests: XCTestCase {
    func testRulesSurviveFullPrompt() {
        let messages = SessionContext().messages(prompt: CopilotSettings.developerPrompt, rules: CopilotSettings.interviewRule, history: [], question: "Що таке лід?", code: "", topic: "", budget: 3200)
        XCTAssertTrue(messages[0].content.hasPrefix(CopilotSettings.developerPrompt))
        XCTAssertTrue(messages[0].content.hasSuffix(CopilotSettings.interviewRule))
    }
    func testTermsInUkrainianSentenceStayUkrainian() {
        for question in ["що робить useEffect", "поясни getElementById і Promise.all", "Що таке closure?", "навіщо тут async", "що таке event loop", "а як працює Promise all"] {
            XCTAssertEqual(AnswerLanguage.detect(question), .ukrainian, question)
            XCTAssertEqual(AnswerLanguage.detect(question, current: .english), .ukrainian, question)
        }
    }
    func testEnglishQuestions() {
        for question in ["What does useEffect do?", "Tell me about a conflict in your team", "How would you design a REST API?", "what's the difference between let and const"] {
            XCTAssertEqual(AnswerLanguage.detect(question), .english, question)
        }
        XCTAssertEqual(AnswerLanguage.detect("useEffect?"), .ukrainian)
        XCTAssertEqual(AnswerLanguage.detect("useEffect?", current: .english), .english)
    }
    func testLanguageSwitch() {
        for text in ["Давай поговоримо англійською", "давайте далі англійською", "Можна англійською?", "Let's speak English", "OK, let's switch to English.", "In English, please"] {
            XCTAssertEqual(AnswerLanguage.switchRequest(text), .english, text)
        }
        for text in ["Давай українською", "Повернімось, давайте українською", "Back to Ukrainian"] {
            XCTAssertEqual(AnswerLanguage.switchRequest(text), .ukrainian, text)
        }
        for text in ["Що таке useEffect?", "Ви знаєте англійську?", "Яким рівнем англійської володієте?"] {
            XCTAssertNil(AnswerLanguage.switchRequest(text), text)
        }
    }
    func testBilingualSpeechLeansToPreferred() {
        XCTAssertEqual(BilingualSpeech.choose(detected: "en", logProbability: log(0.95), preferred: "uk"), "en")
        XCTAssertEqual(BilingualSpeech.choose(detected: "en", logProbability: log(0.6), preferred: "uk"), "uk")
        XCTAssertEqual(BilingualSpeech.choose(detected: "ru", logProbability: log(0.99), preferred: "uk"), "uk")
        XCTAssertEqual(BilingualSpeech.choose(detected: "uk", logProbability: log(0.6), preferred: "en"), "en")
        XCTAssertEqual(BilingualSpeech.preferred("uk+en"), "uk"); XCTAssertNil(BilingualSpeech.preferred("uk"))
    }
    func testInterviewQuestionsAreDetected() {
        for text in ["Розкажіть про себе", "Наведіть приклад конфлікту в команді", "Tell me about yourself", "Walk me through your last project", "Have you worked with Docker", "Would you use Redux here"] {
            XCTAssertTrue(QuestionDetectionService.isQuestion(text), text)
        }
    }
    func testEnglishCodeQuestions() {
        for text in ["Where is fetchWeather used", "What did you do in lab 5", "What does line 14 do", "What is in your project"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(text), text)
        }
        XCTAssertFalse(CodeQuestionRouter.needsCode("Where do you see yourself in five years"))
    }
    func testDirectionsFitWhisperPrompt() {
        for profile in SpeechVocabulary.profiles {
            XCTAssertFalse(SpeechVocabulary.label(profile).isEmpty)
            if !["General", "Mathematics"].contains(profile) { XCTAssertLessThanOrEqual(SpeechVocabulary.text(profile: profile, custom: "").count, 420, profile) }
        }
        XCTAssertEqual(SpeechVocabulary.hint("General"), "")
        XCTAssertTrue(SpeechVocabulary.hint("CRM").contains("CRM"))
    }
    func testV12MovesUkrainianToBilingual() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 11, "language": "uk"]).write(to: store.url)
        let settings = try store.load()
        XCTAssertEqual(settings.language, "uk+en"); XCTAssertFalse(settings.interviewMode)
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 11, "language": "en"]).write(to: store.url)
        XCTAssertEqual(try store.load().language, "en")
    }
}

final class VacancyTests: XCTestCase {
    func testVacancyReachesSelfContainedQuestion() {
        let messages = SessionContext().messages(prompt: "p", pinned: [("Вакансія (дані):", "Шукаємо Junior Frontend: React, TypeScript")], history: [], question: "Що таке замикання?", code: "", topic: "тема", budget: 4000, includeConversation: false)
        XCTAssertTrue(messages.last!.content.contains("Вакансія (дані):\nШукаємо Junior Frontend"))
        XCTAssertFalse(messages.last!.content.contains("тема"))
        XCTAssertFalse(SessionContext().messages(prompt: "p", history: [], question: "q", code: "", topic: "", budget: 4000).last!.content.contains("Вакансія"))
    }
}

final class InterviewRoutingTests: XCTestCase {
    func testInterviewYouIsAboutTheCandidate() {
        for text in ["Які у вас сильні сторони?", "Що вам найбільше сподобалось у вашому проєкті?", "Який результат ви отримали?", "Що робить useEffect?", "Чому ви обрали React у проєкті?"] {
            XCTAssertFalse(CodeQuestionRouter.needsCode(text, interview: true), text)
        }
        for text in ["Що робить 14 рядок?", "Що ви зробили в 5 лабі?", "Покажіть у коді, де fetchWeather", "Що в файлі app.component.ts?", "What is in your code here"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(text, interview: true), text)
        }
        XCTAssertTrue(CodeQuestionRouter.needsCode("Які у вас сильні сторони?")) // outside an interview «у вас» still means the user's code
    }
    func testAskingAboutSkillDoesNotSwitchLanguage() {
        for text in ["Ви говорите англійською?", "Do you speak English?", "Як добре ви знаєте англійську?", "Can you speak English fluently?"] {
            XCTAssertNil(AnswerLanguage.switchRequest(text), text)
        }
        for text in ["Can we continue in English?", "Давайте перейдемо на англійську"] {
            XCTAssertEqual(AnswerLanguage.switchRequest(text), .english, text)
        }
    }
    func testVacancyDoesNotSqueezeConversation() {
        var context = SessionContext(); context.append(speaker: "Співрозмовник", text: "Попередня репліка про досвід")
        let messages = context.messages(prompt: String(repeating: "p", count: 1400), rules: CopilotSettings.interviewRule, pinned: [("Вакансія (дані):", String(repeating: "v", count: 5000))], history: [], question: "Розкажіть про себе", code: "", topic: "Я: 8 лаб з Angular", budget: 4000)
        let user = messages.last!.content
        XCTAssertTrue(user.contains("Я: 8 лаб з Angular")); XCTAssertTrue(user.contains("Попередня репліка"))
        XCTAssertTrue(user.contains(String(repeating: "v", count: 3000))); XCTAssertFalse(user.contains(String(repeating: "v", count: 3001)))
    }
}

final class EnglishFragmentTests: XCTestCase {
    func testHangingEnglishWordsWait() {
        for text in ["Tell me about", "What is the", "Walk me through your"] { XCTAssertTrue(QuestionInbox.incomplete(text), text) }
        for text in ["Tell me about yourself", "What is a closure?"] { XCTAssertFalse(QuestionInbox.incomplete(text), text) }
    }
}

final class DevSpeechTests: XCTestCase {
    func testDevSpeechRuleUsesSpokenTermsAndSurvivesFullPrompt() {
        XCTAssertTrue(CopilotSettings.devSpeechRule.contains("хендшейк (не рукостискання)"))
        let messages = SessionContext().messages(prompt: CopilotSettings.developerPrompt, rules: CopilotSettings.devSpeechRule + "\n" + CopilotSettings.interviewRule, history: [], question: "Як працює TLS?", code: "", topic: "", budget: 4000)
        XCTAssertTrue(messages[0].content.contains("деплоїмо на прод")); XCTAssertTrue(messages[0].content.hasSuffix(CopilotSettings.interviewRule))
    }
}

final class FollowUpTests: XCTestCase {
    func testShortFollowUpGetsPreviousAnswer() {
        for text in ["Чому?", "А як?", "А якщо 0?", "Навіщо?"] { XCTAssertFalse(QuestionContextRouter.isSelfContained(text), text) }
        var context = SessionContext()
        context.append(speaker: "Питання", text: "Які межові значення ви б перевірили для віку 18–65?")
        context.append(speaker: "Підказка асистента", text: "Я б перевірив 17, 18, 65 і 66.")
        let user = context.messages(prompt: "p", rules: CopilotSettings.directAnswerRule, history: [], question: "Чому?", code: "", topic: "", budget: 4000).last!.content
        XCTAssertTrue(user.contains("17, 18, 65 і 66"))
    }
}

final class DocumentIndexTests: XCTestCase {
    func testDocxEquationsAndTablesBecomeText() {
        let xml = """
        <w:document xmlns:w="w" xmlns:m="m"><w:body>
        <w:p><w:r><w:t>Дисперсія:</w:t></w:r><m:oMath><m:r><m:t>D=</m:t></m:r><m:f><m:num><m:r><m:t>1</m:t></m:r></m:num><m:den><m:r><m:t>n</m:t></m:r></m:den></m:f><m:nary><m:naryPr><m:chr m:val="∑"/></m:naryPr><m:e><m:sSup><m:e><m:r><m:t>x</m:t></m:r></m:e><m:sup><m:r><m:t>2</m:t></m:r></m:sup></m:sSup></m:e></m:nary></m:oMath></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>5</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>
        """
        let text = DocxText.text(fromDocumentXML: Data(xml.utf8))
        XCTAssertTrue(text.contains("Дисперсія:D=(1)/(n)∑x^(2)"), text)
        XCTAssertTrue(text.contains("x | 5"), text); XCTAssertFalse(text.contains("5 |"), text)
    }
    func testOnlyMatchingPassagesGoOut() {
        let filler = (1...40).map { "Абзац \($0) про інтерфейс програми, кнопки і налаштування вікна." }.joined(separator: "\n")
        let index = DocumentIndex(documents: [("lab5.docx", filler + "\nДисперсія вибірки дорівнює середньому квадрату відхилень від середнього.\n" + filler)])
        let context = index.context(for: "Яка формула дисперсії?", limit: 1200)
        XCTAssertTrue(context.contains("Дисперсія вибірки")); XCTAssertTrue(context.hasPrefix("[lab5.docx]"))
        XCTAssertLessThanOrEqual(context.count, 1200)
        XCTAssertEqual(index.context(for: "що таке", limit: 1200), "")
    }
    func testNotationWithDigitsIsSearchable() {
        let filler = (1...40).map { "Абзац \($0) про інтерфейс програми, кнопки і налаштування вікна." }.joined(separator: "\n")
        let index = DocumentIndex(documents: [("lab.docx", filler + "\nRₖ² — частка дисперсії, пояснена іншими ознаками.\n" + filler)])
        XCTAssertTrue(index.context(for: "Що таке R2?", limit: 1200).contains("частка дисперсії"))
        XCTAssertTrue(DocumentIndex.terms("Що таке R2 і X1?").isSuperset(of: ["r2", "x1"]))
        XCTAssertFalse(DocumentIndex.terms("що таке ми ok").contains("ok"))
    }
    func testSmallMaterialsGoWhole() {
        let index = DocumentIndex(documents: [("note.txt", "Короткий конспект: мода — найчастіше значення.")])
        XCTAssertTrue(index.context(for: "Розкажіть про лабу").contains("мода"))
    }
    func testLongParagraphIsSplit() {
        let chunks = DocumentIndex.chunks(String(repeating: "Речення про вибірку. ", count: 200))
        XCTAssertGreaterThan(chunks.count, 3); XCTAssertTrue(chunks.allSatisfy { $0.count <= 900 })
    }
}

final class RealDocxTests: XCTestCase {
    func testWordFileMadeByTextutilIsRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("lab.txt"); try "Лабораторна 5\nМедіана — середнє значення впорядкованої вибірки.".write(to: source, atomically: true, encoding: .utf8)
        let convert = Process(); convert.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        convert.arguments = ["-convert", "docx", source.path, "-output", directory.appendingPathComponent("lab.docx").path]
        try convert.run(); convert.waitUntilExit()
        let text = try DocxText.text(fromDocx: directory.appendingPathComponent("lab.docx"))
        XCTAssertTrue(text.contains("Медіана — середнє значення"), text)
        XCTAssertThrowsError(try DocxText.text(fromDocx: source))
    }
}
