import XCTest
@testable import LocalCopilotCore

final class LabDefenseGuideTests: XCTestCase {
    private var profile: LabDefenseProfile {
        LabDefenseProfile.detect(root: "/tmp/lab1_iad_pharmacy", files: [ProjectCodeFile(path: "math_statistics.py", text: ""), ProjectCodeFile(path: "data_processing.py", text: "")])!
    }
    func testAllProvidedQuestionsRetrieveTheirReviewedAnswer() {
        XCTAssertEqual(LabDefenseGuide.cards.count, 35)
        for card in LabDefenseGuide.cards {
            XCTAssertEqual(LabDefenseGuide.matching(card.question).first?.id, card.id, card.question)
            XCTAssertEqual(LabDefenseGuide.exactCard(question: card.question.uppercased().replacingOccurrences(of: "?", with: ""))?.id, card.id)
            // The same bounded context builder used by the app must retain the
            // entire relevant answer, including its mathematical qualification.
            let messages = SessionContext().messages(prompt: LabDefenseProfile.answerPrompt, history: [], question: card.question, code: profile.context(question: card.question), topic: "", budget: 8000)
            XCTAssertTrue(messages.last!.content.contains(card.answer), "Truncated reference \(card.id)")
        }
    }
    func testReadyAnswersFailClosedForChangedConditionsAndSources() {
        XCTAssertNil(LabDefenseGuide.exactCard(question: "Чому не використовується саме T-розподіл, а не нормальний?"))
        XCTAssertNil(LabDefenseGuide.exactCard(question: "Що буде, якщо збільшити R з 400 до 5000?"))
        XCTAssertNil(LabDefenseGuide.exactCard(question: "У ЛР1 аптеки чому в твоєму варіанті обрано Uniform, а не Normal?"))
        XCTAssertNil(LabDefenseGuide.exactCard(question: "Чому при N≠1000 оцінки стабільніші, ніж при N=50?"))
        let expected = ["sample.py": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"] // SHA256(abc)
        XCTAssertTrue(LabDefenseGuide.matchesFingerprints([ProjectCodeFile(path: "sample.py", text: "abc")], expected: expected))
        XCTAssertFalse(LabDefenseGuide.matchesFingerprints([ProjectCodeFile(path: "sample.py", text: "abcd")], expected: expected))
        XCTAssertFalse(LabDefenseGuide.matchesFingerprints([], expected: expected))
        XCTAssertFalse(LabDefenseGuide.matchesReviewedSources([]))
    }
    func testSpokenParaphrasesRouteToRightMethod() {
        let cases: [(String, Int)] = [
            ("Навіщо перевіряти і ліву і праву сторону стрибка емпіричної функції?", 3),
            ("Чому рівномірний закон обрали замість нормального?", 4),
            ("Межі а та бе це мінімум і максимум чи метод моментів?", 7),
            ("Тета нуль і тета з шапочкою це різні речі?", 9),
            ("Чому не взяли готовий random.uniform?", 12),
            ("Що міняє сід 42?", 14),
            ("Ен це розмір вибірки а ер кількість повторень?", 15),
            ("Чим емпіричний SD відрізняється від теоретичного SE?", 18),
            ("Чому розкид SD(t) приблизно одиниця?", 21),
            ("чому використовуєтся саме T розподіл", 26),
            ("Якщо зробити 4000 повторень замість 400?", 27),
            ("Дельта ен це формула з методички чи робоча характеристика?", 30),
            ("Нащо дев'ятсот секунд замінювали через збій датчика?", 33)
        ]
        for (question, id) in cases { XCTAssertTrue(LabDefenseGuide.matching(question).map(\.id).contains(id), "Wrong references for \(question): \(LabDefenseGuide.matching(question).map(\.id))") }
    }
    func testReferenceDoesNotLeakLiftAnswersIntoExplicitPharmacyQuestion() {
        let context = profile.context(question: "ЛР1 аптеки: чому очищення не видаляє реальні 72 і 63?")
        XCTAssertTrue(context.contains("реальне зростання попиту"))
        XCTAssertFalse(context.contains("Перевірені зразки"))
        XCTAssertFalse(context.contains("42.81818182"))
        XCTAssertTrue(LabDefenseGuide.matching("Чим відрізняються Promise і callback?").isEmpty)
        XCTAssertTrue(LabDefenseGuide.matching("Що таке дисперсія?").isEmpty)
    }
    func testStatisticalQualificationsAreAvailableToModel() {
        XCTAssertTrue(profile.context(question: LabDefenseGuide.cards[4].question).contains("усе одно обчислює D"))
        XCTAssertTrue(profile.context(question: LabDefenseGuide.cards[17].question).contains("середнє оцінене SE"))
        XCTAssertTrue(profile.context(question: LabDefenseGuide.cards[25].question).contains("точного T-розподілу"))
        XCTAssertTrue(profile.context(question: LabDefenseGuide.cards[26].question).contains("200 до 500"))
        XCTAssertTrue(profile.context(question: LabDefenseGuide.cards[29].question).contains("робоче визначення"))
        XCTAssertLessThan(LabDefenseProfile.answerPrompt.count, 2000)
        for term in ["ECDF", "SE", "SD", "тета нуль", "RMSE"] { XCTAssertTrue(SpeechVocabulary.text(profile: "Mathematics", custom: "").contains(term)) }
    }
}
