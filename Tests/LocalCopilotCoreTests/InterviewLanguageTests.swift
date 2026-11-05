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
        let messages = SessionContext().messages(prompt: "p", vacancy: "Шукаємо Junior Frontend: React, TypeScript", history: [], question: "Що таке замикання?", code: "", topic: "тема", budget: 4000, includeConversation: false)
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
        let messages = context.messages(prompt: String(repeating: "p", count: 1400), rules: CopilotSettings.interviewRule, vacancy: String(repeating: "v", count: 5000), history: [], question: "Розкажіть про себе", code: "", topic: "Я: 8 лаб з Angular", budget: 4000)
        let user = messages.last!.content
        XCTAssertTrue(user.contains("Я: 8 лаб з Angular")); XCTAssertTrue(user.contains("Попередня репліка"))
        XCTAssertTrue(user.contains(String(repeating: "v", count: 2500))); XCTAssertFalse(user.contains(String(repeating: "v", count: 2501)))
    }
}

final class EnglishFragmentTests: XCTestCase {
    func testHangingEnglishWordsWait() {
        for text in ["Tell me about", "What is the", "Walk me through your"] { XCTAssertTrue(QuestionInbox.incomplete(text), text) }
        for text in ["Tell me about yourself", "What is a closure?"] { XCTAssertFalse(QuestionInbox.incomplete(text), text) }
    }
}
