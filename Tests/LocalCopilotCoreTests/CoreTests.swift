import XCTest
import CoreGraphics
@testable import LocalCopilotCore
final class CoreTests: XCTestCase {
    func testQuestionInboxPreservesContextAtQuestionTime() {
        var context = SessionContext(); var inbox = QuestionInbox(); let now = Date()
        context.append(speaker: "Співрозмовник", text: "Розглядаємо звіт магазину.")
        inbox.append("Що означає ексцес?", source: "Співрозмовник", context: context, at: now)
        context.append(speaker: "Співрозмовник", text: "Тепер переходимо до складу.")
        inbox.append("Що означає ексцес?", source: "Співрозмовник", context: context, at: now.addingTimeInterval(1))
        inbox.append("Тепер переходимо до складу.", source: "Співрозмовник", context: context)
        XCTAssertEqual(inbox.entries.count, 1)
        XCTAssertTrue(inbox.entries[0].context.recent.contains("магазину"))
        XCTAssertFalse(inbox.entries[0].context.recent.contains("складу"))
    }
    func testMathematicsVocabularyAndTermNormalization() {
        XCTAssertTrue(SpeechVocabulary.text(profile: "Mathematics", custom: "").contains("ексцес"))
        XCTAssertTrue(QuestionDetectionService.isQuestion("Ексцес"))
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Що означає ексцез?"), "Що означає ексцес?")
        XCTAssertFalse(QuestionDetectionService.isQuestion("Ми порахували ексцес і завершили роботу"))
    }
    func testProjectReadsFullFileAndSkipsDependenciesAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("demo.ts")
        let text = String(repeating: "const item = 1;\n", count: 2500)
        try text.write(to: source, atomically: true, encoding: .utf8)
        try "ignored".write(to: root.appendingPathComponent("node_modules/dep.ts"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.ts"), withDestinationURL: source)
        let index = try ProjectCodeIndex.load(root: root)
        XCTAssertEqual(index.files.map(\.path), ["demo.ts"])
        XCTAssertEqual(index.files.first?.text, text)
    }
    func testCodeRetrievesLineBeyondScreenAndNamesFile() {
        let text = (1...250).map { "const value\($0) = \($0);" }.joined(separator: "\n")
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-06/src/app/demo.ts", text: text)])
        let result = index.search(question: "Що означає 129 рядок?", active: "lab-06/src/app/demo.ts")
        XCTAssertEqual(result.exactLine, 129); XCTAssertTrue(result.context.contains("129: const value129 = 129;")); XCTAssertFalse(result.context.contains("1: const value1 = 1;"))
    }
    func testSingleFileFolderAnswersLineWithoutChoosingFile() {
        let text = (1...150).map { "const value\($0) = \($0);" }.joined(separator: "\n")
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "src/lab.ts", text: text)])
        let result = index.search(question: "Що в рядку 129?", active: nil)
        XCTAssertEqual(result.files, ["src/lab.ts"])
        XCTAssertTrue(result.context.contains("129: const value129 = 129;"))
    }
    func testAmbiguousEditorAndExplicitLab() {
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-05/demo.ts", text: "const selected = items.find(item => item.id);"), ProjectCodeFile(path: "lab-06/demo.ts", text: "const selected = items.find(item => item.id);")])
        XCTAssertNil(index.matchVisible(source: "WebStorm demo.ts", visible: "const selected = items.find(item => item.id);"))
        XCTAssertEqual(index.search(question: "Лаба 6 demo.ts рядок 1", active: nil).files, ["lab-06/demo.ts"])
        XCTAssertTrue(index.search(question: "рядок 129", active: nil).context.contains("Уточни"))
    }
    func testCodeLineAliasesAndOutOfRange() {
        for question in ["в 129 строці", "на рядку 129", "line 129", "129-му рядку"] { XCTAssertEqual(ProjectCodeIndex.requestedLine(question), 129, question) }
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "a.ts", text: "const a = 1;")])
        XCTAssertTrue(index.search(question: "рядок 129", active: "a.ts").context.contains("рядка 129 немає"))
    }
    func testProjectWideSearchPrioritizesStorageOverActiveDashboard() {
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-06/dashboard.component.ts", text: "favorites = this.favoritesStorage.load(); refreshSavedFavorites() { this.favoritesStorage.save(this.favorites); }"), ProjectCodeFile(path: "lab-06/services/favorites-storage.service.ts", text: "class FavoritesStorageService { save(items) { localStorage.setItem(key, JSON.stringify(items)); } load() { return JSON.parse(localStorage.getItem(key)); } }")])
        let result = index.search(question: "Де у лабі 6 зберігається вибране після перезавантаження?", active: "lab-06/dashboard.component.ts")
        XCTAssertEqual(result.files.first, "lab-06/services/favorites-storage.service.ts")
    }
    func testCurrentFunctionUsesActiveFileAndCursorWithoutLabNumber() {
        let body = (1...150).map { number in number == 87 ? "function calculateTotal() { return prices.reduce((a, b) => a + b, 0); }" : "const item\(number) = \(number);" }.joined(separator: "\n")
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-03/source.ts", text: body), ProjectCodeFile(path: "lab-06/other.ts", text: "function other() {}")])
        let result = index.search(question: "Що робить ця функція тут?", active: "lab-03/source.ts", focusLine: 87, focusedSymbol: "calculateTotal(), function")
        XCTAssertEqual(result.files, ["lab-03/source.ts"])
        XCTAssertTrue(result.context.contains("87: function calculateTotal()"))
        XCTAssertTrue(result.context.contains("Активний символ IDE: calculateTotal()"))
        XCTAssertFalse(result.context.contains("\n1: const item1"))
    }
    func testNamedFunctionOverridesCursorInOpenFile() {
        let body = (1...250).map { number in number == 129 ? "function getUserByID(id: number) { return users.find(user => user.id === id); }" : "const unrelatedItem\(number) = \(number);" }.joined(separator: "\n")
        let path = "lab-01/src/app/users.ts"
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: path, text: body)])
        let question = "Що робить getUserByID у відкритому файлі?"
        XCTAssertFalse(ProjectCodeIndex.refersToCurrentCode(question))
        let result = index.search(question: question, active: path, focusLine: 1, focusedSymbol: "unrelatedItem1")
        XCTAssertEqual(result.files, [path])
        XCTAssertTrue(result.context.contains("129: function getUserByID"))
        XCTAssertFalse(result.context.contains("Активний символ IDE: unrelatedItem1"))
    }
    func testDirectFunctionQuestionUsesDefinitionInsteadOfCallSites() {
        let index = ProjectCodeIndex(files: [
            ProjectCodeFile(path: "src/app/lab-01.ts", text: "import { getUserByID } from './users';\nconst user = getUserByID(0);"),
            ProjectCodeFile(path: "src/app/users.ts", text: "export function getUserByID(id: number): User | undefined {\n  if (id <= 0) return undefined;\n  return users.find(user => user.id === id);\n}")
        ])
        let result = index.search(question: "Де визначено getUserByID і що повертає при id = 0?", active: nil, budget: 2400)
        XCTAssertEqual(result.files, ["src/app/users.ts"])
        XCTAssertTrue(result.context.contains("id <= 0"))
    }
    func testCodeSymbolSearchAndBudget() {
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "favorites.ts", text: "function persistFavorites() { storage.save(items); }"), ProjectCodeFile(path: "orders.ts", text: "function getOrders() { return []; }")])
        let result = index.search(question: "Де збереження вибраного?", active: nil, budget: 1000)
        XCTAssertEqual(result.files.first, "favorites.ts"); XCTAssertLessThan(result.context.count, 1000)
    }
    func testCodeQuestionsRouteOnlyWhenProjectContextIsRelevant() {
        for question in ["А що у вас значить цей метод?", "Ось 197 строка, що вона робить?", "Де в коді зберігається вибране?", "Що робить getUserByID?", "Де у лабі 6 визначено сервіс?", "Що в такій-то строці?"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(question), question)
        }
        for question in ["Чим відрізняються Promise, async/await і callback?", "Що таке статична типізація?", "Яка сьогодні тема?"] {
            XCTAssertFalse(CodeQuestionRouter.needsCode(question), question)
        }
        XCTAssertTrue(CodeQuestionRouter.needsCode("А чому він повертає undefined?", previousCodeQuestion: true))
        XCTAssertFalse(CodeQuestionRouter.needsCode("А чому він повертає undefined?", previousCodeQuestion: false))
        XCTAssertTrue(QuestionDetectionService.isQuestion("Ось 197 строка шо вона робить"))
    }
    func testLabFolderLineLookupAndEditorOverlay() {
        let original = ProjectCodeIndex(files: [ProjectCodeFile(path: "src/app/users.ts", text: "function oldValue() { return 1; }")], rootName: "lab-01")
        let updated = original.replacing(path: "src/app/users.ts", text: "function newValue() { return 2; }")
        XCTAssertEqual(updated.search(question: "Що у лабі 1 в рядку 1?", active: nil).files, ["src/app/users.ts"])
        XCTAssertTrue(updated.search(question: "Де newValue?", active: nil).context.contains("newValue"))
        XCTAssertFalse(updated.search(question: "Де newValue?", active: nil).context.contains("oldValue"))
    }

    func testClassroomAndOnlineRoutingProfiles() {
        var settings = CopilotSettings(); settings.audioMode = .both; settings.captureMyVoice = true
        settings.applyListeningProfile(.online)
        XCTAssertEqual(settings.effectiveAudioMode, .system); XCTAssertFalse(settings.answerFromMicrophone)
        settings.applyListeningProfile(.classroom)
        XCTAssertEqual(settings.effectiveAudioMode, .microphone); XCTAssertTrue(settings.answerFromMicrophone)
        settings.applyListeningProfile(.custom)
        XCTAssertEqual(settings.effectiveAudioMode, .microphone)
    }
    func chunk(final: Bool = false, id: UUID, window: Int = 0, overlap: Bool = false) -> AudioChunk { AudioChunk(samples: [], source: .system, final: final, utterance: id, window: window, overlapsPrevious: overlap) }
    func testInterimReplacementAndConfirmation() {
        var assembler = TranscriptAssembler(); let id = UUID()
        let first = assembler.accept("What is", chunk: chunk(id: id))
        XCTAssertEqual(first.confirmed, ""); XCTAssertEqual(first.interim, "What is"); XCTAssertNil(first.completedUtterance)
        let final = assembler.accept("What is a closure?", chunk: chunk(final: true, id: id))
        XCTAssertEqual(final.confirmed, "What is a closure?"); XCTAssertEqual(final.interim, ""); XCTAssertEqual(final.completedUtterance, "What is a closure?")
    }
    func testOverlapOnlyWithinSameUtterance() {
        var assembler = TranscriptAssembler(); let id = UUID()
        _ = assembler.accept("Explain a React hook", chunk: chunk(id: id))
        let final = assembler.accept("React hook and its lifecycle?", chunk: chunk(final: true, id: id, window: 1, overlap: true))
        XCTAssertEqual(final.confirmed, "Explain a React hook and its lifecycle?")
        let second = assembler.accept("Explain a React hook and its lifecycle?", chunk: chunk(final: true, id: UUID()))
        XCTAssertEqual(second.confirmed, "Explain a React hook and its lifecycle? Explain a React hook and its lifecycle?")
    }
    func testUkrainianCaseInsensitiveOverlap() { XCTAssertEqual(TranscriptAssembler.removeOverlap(previous: "Що таке React?", next: "таке react і hooks?"), "і hooks?") }
    func testThinkingTagsSplitAcrossPackets() {
        var parser = ThinkingStreamParser()
        for token in ["<thi", "nk>Reason", "ing</th", "ink>Від", "повідь"] { parser.append(token) }
        parser.finish(); XCTAssertEqual(parser.answer, "Відповідь"); XCTAssertEqual(parser.thinking, "Reasoning")
    }
    func testOrphanThinkingCloseAndPlainCode() {
        var parser = ThinkingStreamParser()
        parser.append("draft</think>Actual answer"); parser.finish()
        XCTAssertEqual(parser.answer, "Actual answer"); XCTAssertEqual(parser.thinking, "draft")
        var code = ThinkingStreamParser(); code.append("if (a < b) return a;"); code.finish(); XCTAssertEqual(code.answer, "if (a < b) return a;")
    }
    func testWhisperNoiseLabelsAreNotSpeech() {
        XCTAssertFalse(SpeechRecognitionService.isSpeechText(" [музика] "))
        XCTAssertFalse(SpeechRecognitionService.isSpeechText("(keyboard clacks)"))
        XCTAssertFalse(SpeechRecognitionService.isSpeechText(""))
        XCTAssertTrue(SpeechRecognitionService.isSpeechText("Що таке SQL та NoSQL?"))
    }
    func testShortFollowUpQuestions() {
        XCTAssertTrue(QuestionDetectionService.isQuestion("А чому?"))
        XCTAssertTrue(QuestionDetectionService.isQuestion("Why?"))
        XCTAssertFalse(QuestionDetectionService.isQuestion("Так."))
    }
    func testShortQuestionsWithoutWhisperPunctuation() {
        for text in ["Чому", "Ну а як", "Так, а що тут", "Добре. Поясніть", "Шо таке проміс", "Статична типізація", "Рейс кондишин", "А getUserByID", "Що тут означає save()"] {
            XCTAssertTrue(QuestionDetectionService.isQuestion(text), text)
        }
        for text in ["Так", "Добре", "Ми використовуємо проміси", "Це статична типізація", "Проміси виконуються асинхронно"] {
            XCTAssertFalse(QuestionDetectionService.isQuestion(text), text)
        }
    }
    func testRepeatedQuestionCanBeAnsweredAgainLater() {
        var detector = QuestionDetectionService()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNotNil(detector.completed("А чому", at: start))
        XCTAssertNil(detector.completed("А чому?", at: start.addingTimeInterval(2)))
        XCTAssertNotNil(detector.completed("А чому?", at: start.addingTimeInterval(9)))
    }
    func testAudioDiscontinuityRetainsConfirmedTranscript() {
        var assembler = TranscriptAssembler()
        _ = assembler.accept("Перший завершений текст.", chunk: chunk(final: true, id: UUID()))
        _ = assembler.accept("Незавершений", chunk: chunk(id: UUID()))
        assembler.discontinuity()
        let next = assembler.accept("Наступне запитання?", chunk: chunk(final: true, id: UUID()))
        XCTAssertEqual(next.confirmed, "Перший завершений текст. Наступне запитання?")
        XCTAssertEqual(next.completedUtterance, "Наступне запитання?")
    }
    func testQuestionDetection() {
        for text in ["Що таке замикання?", "Як працює React", "Поясніть різницю між SQL і NoSQL", "Could you explain dependency injection", "А якщо запит падає", "What about caching"] { XCTAssertTrue(QuestionDetectionService.isQuestion(text), text) }
        for text in ["Дякую за пояснення.", "This implementation works.", "Так.", ""] { XCTAssertFalse(QuestionDetectionService.isQuestion(text), text) }
    }
    func testClassroomImperativesAndRaceConditionSpeech() {
        XCTAssertTrue(QuestionDetectionService.isQuestion("Покажіть, де тут функція розрахунку"))
        XCTAssertTrue(QuestionDetectionService.isQuestion("Знайди реалізацію збереження"))
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Що таке рейс кондишин і як його уникати?"), "Що таке race condition і як його уникати?")
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Коли вилітає рейс до Києва?"), "Коли вилітає рейс до Києва?")
    }
    func testComparisonQuestionWithoutASRPunctuation() {
        let examples = ["Чим відрізняються Promise, async/await і callback", "Чим ведрізняються промис, авейт і хвилин. і холлбек.", "Чим відрізняються Let, Const і Va.", "У чому різниця між SQL і NoSQL", "В чому різниця між процесом і тредом", "Скільки потоків використовує Node.js", "Навіщо потрібен кеш"]
        for text in examples {
            var detector = QuestionDetectionService()
            XCTAssertEqual(detector.completed(text), text)
            XCTAssertNil(detector.completed(text))
        }
        for text in ["З цим усе працює.", "Проміси виконуються асинхронно.", "Цим методом ми кешуємо дані."] { XCTAssertFalse(QuestionDetectionService.isQuestion(text)) }
    }
    func testStaticTypingSpeechCorrectionPreservesOtherUses() {
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Що таке естетично-тепізація?"), "Що таке статична типізація?")
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Що таке естетична типізація?"), "Що таке статична типізація?")
        for text in ["Це естетично виглядає.", "Що таке динамічна типізація?", "Чим корисна статична типізація?"] { XCTAssertEqual(TechnicalQuestionNormalizer.normalize(text), text) }
    }
    func testSpeechTermNormalizationRequiresAsyncContext() {
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Чим відрізняється проміс, асенкавит і колбек?"), "Чим відрізняється Promise, async/await і callback?")
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Чим відрізняються промис, айсінг, овейд і колбек."), "Чим відрізняються Promise, async/await і callback.")
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Чим відрізняються проміс, асинк/авейт і холлбек?"), "Чим відрізняються Promise, async/await і callback?")
        for text in ["Що таке айсінг і як ним покрити торт?", "Скільки хвилин чекати?", "Промис і айсінг", "Чим відрізняються Promise, async/await і callback?"] { XCTAssertEqual(TechnicalQuestionNormalizer.normalize(text), text) }
        // Do not invent missing async terms from the first, more damaged transcript.
        XCTAssertEqual(TechnicalQuestionNormalizer.normalize("Чим ведрізняються промис, авейт і хвилин. і холлбек."), "Чим ведрізняються Promise, авейт і хвилин. і callback.")
    }
    func testQuestionDuplicateSuppression() {
        var detector = QuestionDetectionService()
        XCTAssertNotNil(detector.completed("Як працює React?")); XCTAssertNil(detector.completed("Як працює React?")); XCTAssertNotNil(detector.completed("А як працює useEffect?"))
    }
    func testQwenThinkingControl() {
        let messages = [ChatMessage(role: "user", content: "Поясни React")]
        let off = OllamaService.requestMessages(messages, model: "qwen3:4b", thinking: false, supported: true)
        XCTAssertEqual(off.last?.role, "assistant"); XCTAssertEqual(off.last?.content, "<think>\n</think>\n\n")
        XCTAssertEqual(OllamaService.requestMessages(messages, model: "qwen3:4b", thinking: true, supported: true), messages)
        XCTAssertEqual(OllamaService.requestMessages(messages, model: "dolphin3:8b", thinking: false, supported: false), messages)
    }
    func testPacketUnicodeThinkingAndErrors() throws {
        let packet = try OllamaPacket.parse("{\"message\":{\"content\":\"Привіт 👋\",\"thinking\":\"reason\"},\"done\":false}")
        XCTAssertEqual(packet.message?.content, "Привіт 👋"); XCTAssertEqual(packet.message?.thinking, "reason"); XCTAssertEqual(packet.done, false)
        XCTAssertTrue(try OllamaPacket.parse("{\"done\":true}").done == true)
        XCTAssertThrowsError(try OllamaPacket.parse("{\"error\":\"model not found\"}"))
        XCTAssertThrowsError(try OllamaPacket.parse("not-json"))
    }
    func testHTTPFailures() {
        let url = URL(string: "http://127.0.0.1:11434/api/chat")!
        XCTAssertThrowsError(try OllamaService.check(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!))
        XCTAssertNoThrow(try OllamaService.check(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
    }
    func testContextIsBoundedAndKeepsPairs() {
        let history = (0..<10).flatMap { _ in [ChatMessage(role: "user", content: String(repeating: "u", count: 100)), ChatMessage(role: "assistant", content: String(repeating: "a", count: 100))] }
        let messages = ContextBuilder.messages(prompt: "Be concise", history: history, question: String(repeating: "q", count: 900), budget: 600)
        XCTAssertLessThanOrEqual(messages.reduce(0) { $0 + $1.content.count }, 600)
        XCTAssertEqual(messages.first?.role, "system"); XCTAssertEqual(messages.last?.role, "user")
        XCTAssertEqual((messages.count - 2) % 2, 0)
    }
    func testSessionContextKeepsRolesAndCodeForFollowUp() {
        var context = SessionContext()
        context.append(speaker: "Співрозмовник", text: "Обговорюємо масив items і map у JavaScript")
        context.append(speaker: "Я", text: "Множу кожний елемент на три")
        context.summary = "Раніше порівняли Promise та callback"
        let messages = context.messages(prompt: "Be concise", history: [], question: "А чому?", code: "const items = [2, 4, 6];\nconsole.log(items.map(n => n * 3));", topic: "Захист JavaScript", budget: 6000)
        let user = messages.last!.content
        XCTAssertTrue(user.contains("[Я] Множу")); XCTAssertTrue(user.contains("[Співрозмовник]"))
        XCTAssertTrue(user.contains("items.map")); XCTAssertTrue(user.contains("Promise та callback"))
        XCTAssertTrue(user.hasSuffix("А чому?"))
    }
    func testIndependentQuestionSkipsOldConversationButKeepsCode() {
        var context = SessionContext()
        context.append(speaker: "Співрозмовник", text: "Інша тема: SQL індекси")
        context.summary = "Раніше обговорювали транзакції"
        XCTAssertTrue(QuestionContextRouter.isSelfContained("Чим відрізняються Promise, async/await і callback?"))
        XCTAssertTrue(QuestionContextRouter.isSelfContained("Що робить getUserByID?"))
        XCTAssertFalse(QuestionContextRouter.isSelfContained("А чому він повертає undefined?"))
        XCTAssertFalse(QuestionContextRouter.isSelfContained("Що робить ця функція тут?"))
        let messages = context.messages(prompt: "Відповідай коротко", history: [], question: "Що робить getUserByID?", code: "63: function getUserByID() { return undefined; }", topic: "Стара тема", budget: 3200, includeConversation: false)
        XCTAssertTrue(messages.last!.content.contains("63: function getUserByID"))
        XCTAssertFalse(messages.last!.content.contains("SQL індекси"))
        XCTAssertFalse(messages.last!.content.contains("Стара тема"))
    }
    func testSessionContextRollupDoesNotConsumeNewTurns() {
        var context = SessionContext()
        for index in 0..<100 { context.append(speaker: "Співрозмовник", text: "Topic \(index) " + String(repeating: "x", count: 400)) }
        XCTAssertLessThanOrEqual(context.turns.count, 60)
        let snapshot = context.archived
        context.append(speaker: "Я", text: "New turn " + String(repeating: "y", count: 1000))
        context.consumeArchive(snapshot, summary: "Topic is JavaScript")
        XCTAssertEqual(context.summary, "Topic is JavaScript"); XCTAssertTrue(context.recent.contains("New turn"))
        XCTAssertFalse(context.archived.hasPrefix(snapshot))
    }
    func testSessionContextBudgetAndCurrentCodePriority() {
        var context = SessionContext(); context.summary = String(repeating: "s", count: 9000)
        context.append(speaker: "Співрозмовник", text: String(repeating: "t", count: 20000))
        let messages = context.messages(prompt: String(repeating: "p", count: 5000), history: [ChatMessage(role: "user", content: String(repeating: "u", count: 3000)), ChatMessage(role: "assistant", content: String(repeating: "a", count: 3000))], question: "What does this do?", code: "IMPORTANT_CODE " + String(repeating: "c", count: 12000), topic: "Topic", budget: 3000)
        XCTAssertLessThanOrEqual(messages.reduce(0) { $0 + $1.content.count }, 3000)
        XCTAssertTrue(messages.last!.content.contains("IMPORTANT_CODE")); XCTAssertTrue(messages.last!.content.hasSuffix("What does this do?"))
        XCTAssertEqual(messages.first?.role, "system")
    }
    func testOwnMicrophoneRequiresExplicitSelection() {
        var settings = CopilotSettings(); settings.audioMode = .both
        XCTAssertEqual(settings.effectiveAudioMode, .system)
        settings.captureMyVoice = true; XCTAssertEqual(settings.effectiveAudioMode, .both)
        settings.captureMyVoice = false; settings.audioMode = .microphone
        XCTAssertEqual(settings.effectiveAudioMode, .microphone)
    }
    func testVocabularyKeepsCustomTermsAndSupportsGeneral() {
        XCTAssertTrue(SpeechVocabulary.text(profile: "JavaScript", custom: "MyWidget").contains("MyWidget"))
        XCTAssertTrue(SpeechVocabulary.text(profile: "SQL", custom: "").contains("PostgreSQL"))
        XCTAssertTrue(SpeechVocabulary.text(profile: "General", custom: "").contains("race condition"))
        XCTAssertLessThanOrEqual(SpeechVocabulary.text(profile: "Python", custom: String(repeating: "x", count: 3000)).count, 1500)
    }
    func testSettingsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(try store.load(), CopilotSettings())
        var settings = CopilotSettings(); settings.language = "uk"; settings.audioMode = .both; settings.thinking = true
        try store.save(settings); XCTAssertEqual(try store.load(), settings)
        try Data("broken".utf8).write(to: store.url); XCTAssertThrowsError(try store.load())
    }
    func testProgramOutputQuestionsRouteToCodeButConceptsDoNot() {
        for question in ["Що відбувається в програмі далі?", "Де обчислюється середнє?", "Де розраховано дисперсію?", "Звідки і де береться ця вибірка?", "Що виводить програма?", "Скільки відхилили гіпотез?"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(question), question)
        }
        XCTAssertFalse(CodeQuestionRouter.needsCode("Що таке кореляція?"))
        XCTAssertFalse(CodeQuestionRouter.needsCode("Яка кореляція між ознаками?"))
    }
    func testGeneralVocabularyCoversProgrammingNotOnlyJavaScript() {
        XCTAssertEqual(CopilotSettings().vocabularyProfile, "General")
        let terms = SpeechVocabulary.text(profile: "General", custom: "")
        for term in ["Python", "Java", "C++", "Docker", "рекурсія", "поліморфізм", "race condition"] { XCTAssertTrue(terms.contains(term), term) }
        XCTAssertLessThan(terms.count, 800) // leaves room for project terms in the speech prompt
        XCTAssertEqual(SpeechVocabulary.label("General"), "Усі теми")
    }
    func testOpenEditorPhrasesRouteToCode() {
        for question in ["А що тут відбувається?", "Що робить цей клас?", "Що в цьому файлі?", "Навіщо цей цикл?"] { XCTAssertTrue(CodeQuestionRouter.needsCode(question), question) }
    }
    func testV8SettingsEnableIDEScreenshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 9, "claudeSendScreenshots": true, "privateWindow": true]).write(to: store.url)
        var settings = try store.load()
        XCTAssertFalse(settings.claudeSendScreenshots) // version 9 forced it on, so it is reset once
        settings.claudeSendScreenshots = true; try store.save(settings)
        XCTAssertTrue(try store.load().claudeSendScreenshots) // later opt-in sticks
    }
    func testAutomaticAnswersNeverSendTheScreenToTheCloud() {
        XCTAssertFalse(ScreenshotPolicy.sendsImage(allowed: true, cloud: true, automatic: true))
        XCTAssertFalse(ScreenshotPolicy.capturesForCodeQuestion(codeQuestion: true, allowed: true, cloud: true, automatic: true))
        XCTAssertFalse(ScreenshotPolicy.capturesForVisualQuestion(visual: true, allowed: true, cloud: true, automatic: true))
        XCTAssertFalse(ScreenshotPolicy.capturesForVisualQuestion(visual: true, allowed: false, cloud: true, automatic: false)) // the image could not be sent: no 10-second capture
        XCTAssertFalse(ScreenshotPolicy.sendsImage(allowed: false, cloud: true, automatic: false)) // off by default
        XCTAssertTrue(ScreenshotPolicy.sendsImage(allowed: true, cloud: true, automatic: false))
        XCTAssertTrue(ScreenshotPolicy.sendsImage(allowed: false, cloud: false, automatic: true)) // a local model keeps it on the Mac
        XCTAssertTrue(ScreenshotPolicy.capturesForVisualQuestion(visual: true, allowed: true, cloud: false, automatic: true))
        XCTAssertFalse(ScreenshotPolicy.capturesForVisualQuestion(visual: true, allowed: false, cloud: false, automatic: false)) // switched off: not for a local model either
        XCTAssertTrue(ScreenshotPolicy.capturesForVisualQuestion(visual: true, allowed: true, cloud: true, automatic: false))
    }
    func testCaptureComparisonSeesAWindowButNotEqualPictures() throws {
        func picture(panel: CGRect?) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            if let panel { context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(panel) }
            return try XCTUnwrap(context.makeImage())
        }
        let empty = try picture(panel: nil)
        XCTAssertFalse(CaptureComparison.differ(empty, try picture(panel: nil)))
        XCTAssertTrue(CaptureComparison.differ(empty, try picture(panel: CGRect(x: 50, y: 50, width: 200, height: 150))))
    }
    func testProgrammingRuleReachesDefaultPromptButNotCustomOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 10, "systemPrompt": CopilotSettings.previousDeveloperPrompt]).write(to: store.url)
        XCTAssertEqual(try store.load().systemPrompt, CopilotSettings.developerPrompt)
        XCTAssertEqual(try store.load().schemaVersion, 12)
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 10, "systemPrompt": "Мій промпт"]).write(to: store.url)
        XCTAssertEqual(try store.load().systemPrompt, "Мій промпт")
    }
    func testLineNumberIsRecognizedWithAnySpokenEnding() {
        for question in ["що означає три точки в 14-х рядку.", "в 14-му рядку", "14-ому рядку", "14-тому рядку", "14й рядок", "14-й рядок", "14 рядку", "в 14-ій строці", "14-ї строчки", "14-та строка", "рядок 14", "line 14"] {
            XCTAssertEqual(ProjectCodeIndex.requestedLine(question), 14, question)
        }
        for question in ["додай 2 нові рядки", "тут 3 складні стратегії"] { XCTAssertNil(ProjectCodeIndex.requestedLine(question), question) }
    }
    func testSpokenLineQuestionGetsThatLineOfTheOpenFile() {
        let path = "lab-04/src/app/array-result/array-result.component.ts"
        let body = (1...13).map { "// line \($0)" } + ["    this.inputNumbers = [...value];"]
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: path, text: body.joined(separator: "\n")), ProjectCodeFile(path: "lab-01/other.ts", text: "const other = 1;")])
        let question = "що означає три точки в 14-х рядку."
        XCTAssertTrue(CodeQuestionRouter.needsCode(question))
        let result = index.search(question: question, active: path)
        XCTAssertEqual(result.exactLine, 14)
        XCTAssertEqual(result.files, [path])
        XCTAssertTrue(result.context.contains("[...value]"))
    }
    func testSpokenRangeWrittenAsOneNumberFindsBothLines() {
        let path = "lab-04/array-result.component.ts"
        let body = (1...45).map { $0 == 30 ? "const minimum: number | undefined = this.minimum;" : $0 == 31 ? "const maximum: number | undefined = this.maximum;" : "// line \($0)" }
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: path, text: body.joined(separator: "\n"))])
        let result = index.search(question: "Чому ми юзаєм Undefine в 3031 рядку на шо він?", active: path)
        XCTAssertTrue(result.context.contains("30: const minimum"))
        XCTAssertTrue(result.context.contains("31: const maximum"))
        XCTAssertTrue(result.context.contains("рядки 30–31"))
    }
    func testOutOfRangeNumberIsOnlySplitWhenItLooksLikeARange() {
        XCTAssertEqual(ProjectCodeIndex.spokenRange(3031, lineCount: 45), 30...31)
        XCTAssertEqual(ProjectCodeIndex.spokenRange(910, lineCount: 45), 9...10)
        XCTAssertNil(ProjectCodeIndex.spokenRange(129, lineCount: 45)) // 1 and 29 are too far apart
        XCTAssertNil(ProjectCodeIndex.spokenRange(3130, lineCount: 45)) // goes backwards
        XCTAssertNil(ProjectCodeIndex.spokenRange(3031, lineCount: 30)) // past the end of the file
        XCTAssertNil(ProjectCodeIndex.spokenRange(305, lineCount: 45)) // 30 and 5, or 3 and 05
    }
    private var labFiles: [ProjectCodeFile] { [
        ProjectCodeFile(path: "lab-04/src/app/app.component.ts", text: "export class AppComponent {}"),
        ProjectCodeFile(path: "lab-05/src/app/services/weather.service.ts", text: "import axios from 'axios';\nconst apiKey = 'x';\nexport class WeatherService {\n  load() { return axios.get('https://api.weatherapi.com/v1/current.json'); }\n}"),
        ProjectCodeFile(path: "lab-05/src/app/app.component.ts", text: "export class AppComponent { title = 'weather'; }"),
        ProjectCodeFile(path: "lab-06/src/app/services/weather.service.ts", text: "import axios from 'axios';\nconst apiKey = 'x';\nexport class WeatherService {}")
    ] }
    func testLabQuestionInAnyFormSearchesThatLab() {
        let index = ProjectCodeIndex(files: labFiles)
        for question in ["Покажи де ти підключав апі 5 лабі", "де ти підключав апі в 5 лабі", "де юзалось апі в 5-й лабі", "де підключено API у 5-ій лабі", "апі в п'ятій лабі", "апі в п’ятій лабі", "апі в лабі 5", "апі в лаба 5", "апі в лабораторній 5", "апі в лабораторній роботі №5", "апі в lab-05", "апі в lab 5", "де в 5 лабі HTTP запит", "де в 5 лабі запит до сервера"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(question), question)
            let result = index.search(question: question, active: "lab-04/src/app/app.component.ts")
            XCTAssertEqual(result.files.first, "lab-05/src/app/services/weather.service.ts", question)
            XCTAssertFalse(result.files.contains { $0.hasPrefix("lab-06/") || $0.hasPrefix("lab-04/") }, question)
            XCTAssertTrue(result.context.contains("axios.get"), question)
        }
    }
    func testWhereWasItUsedQuestionsGoToTheCode() {
        for question in ["де використовується Promise.all", "де юзалось апі", "де ти використовував axios", "покажи де це написано", "де викликається load", "де імпортується axios"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(question), question)
        }
        for question in ["Що таке проміс?", "Чим відрізняється Promise від async/await?", "Яка столиця Франції?"] {
            XCTAssertFalse(CodeQuestionRouter.needsCode(question), question)
        }
    }
    func testLabWithoutAMatchListsItsFilesInsteadOfNothing() {
        let result = ProjectCodeIndex(files: labFiles).search(question: "де графічний інтерфейс у 5 лабі", active: nil)
        XCTAssertTrue(result.context.contains("lab-05/src/app/app.component.ts"))
        XCTAssertFalse(result.context.contains("lab-06/"))
    }
    private var overviewFiles: [ProjectCodeFile] { [
        ProjectCodeFile(path: "lab-06/README.md", text: "# Практична робота №6\nЗберігає вибране в localStorage."),
        ProjectCodeFile(path: "lab-06/src/app/services/favorites-storage.service.ts", text: "@Injectable()\nexport class FavoritesStorageService {\n  private readonly key = 'k';\n  load(): string[] {\n    if (x) { return []; }\n    return [];\n  }\n  save(items: string[]): void {\n  }\n}"),
        ProjectCodeFile(path: "lab-06/src/app/app.component.spec.ts", text: "describe('App', () => {\n  it('creates the app', () => {\n    const value = 1;\n  });\n});"),
        ProjectCodeFile(path: "lab-06/src/app/app.component.css", text: "secretcss { color: red; }"),
        ProjectCodeFile(path: "lab-06/package.json", text: "{\"name\":\"secretjson\"}"),
        ProjectCodeFile(path: "lab-07/src/app/task.service.ts", text: "export class TaskService {}")
    ] }
    func testWhatDidYouDoInALabGetsAnOverviewOfThatLab() {
        let index = ProjectCodeIndex(files: overviewFiles)
        for question in ["що ти робив в 6 лабі", "що ти робив у шостій лабі", "що ви робили в лабі 6", "що зробив у 6-й лабі", "розкажи про 6 лабу", "опиши лабораторну роботу 6", "про що 6 лаба", "яке завдання в 6 лабі", "що було в lab-06", "що ти там робив у 6 лабі", "що зроблено в шостій лабі", "чим ти займався в 6 лабі", "що писав у лабораторній 6"] {
            XCTAssertTrue(CodeQuestionRouter.needsCode(question), question)
            let context = index.search(question: question, active: "lab-07/src/app/task.service.ts").context
            XCTAssertTrue(context.contains("Зберігає вибране в localStorage"), question)
            XCTAssertTrue(context.contains("export class FavoritesStorageService"), question)
            XCTAssertTrue(context.contains("load(): string[]"), question)
            XCTAssertTrue(context.contains("save(items: string[])"), question)
            XCTAssertTrue(context.contains("creates the app"), question)
            XCTAssertFalse(context.contains("secretcss") || context.contains("secretjson"), question)
            XCTAssertFalse(context.contains("TaskService"), question)
        }
    }
    func testOverviewOutlinesABigFileAndAddsOnlyWhatFits() {
        let big = "export class Big {\n  run(): void {\n    if (secretBody) { work(); }\n  }\n}\n" + String(repeating: "// padding\n", count: 500)
        let files = [ProjectCodeFile(path: "lab-06/big.ts", text: big), ProjectCodeFile(path: "lab-06/small.ts", text: "const smallBody = 1;\nexport function small(): void {\n}")]
        let context = ProjectCodeIndex(files: files).search(question: "що ти робив в 6 лабі", active: nil, budget: 1000).context
        XCTAssertTrue(context.contains("run(): void"))
        XCTAssertFalse(context.contains("secretBody"))
        XCTAssertTrue(context.contains("smallBody"))
        XCTAssertLessThanOrEqual(context.count, 1000)
    }
    func testThisLabUsesTheLabOfTheOpenFile() {
        let index = ProjectCodeIndex(files: overviewFiles)
        XCTAssertTrue(CodeQuestionRouter.needsCode("що ти робив в цій лабі"))
        let context = index.search(question: "що ти робив в цій лабі", active: "lab-06/src/app/app.component.spec.ts").context
        XCTAssertTrue(context.contains("FavoritesStorageService"))
        XCTAssertFalse(context.contains("TaskService"))
    }
    func testSpecificQuestionAboutALabStillSearchesForThatThing() {
        let result = ProjectCodeIndex(files: labFiles).search(question: "розкажи про апі в 5 лабі", active: nil)
        XCTAssertEqual(result.files.first, "lab-05/src/app/services/weather.service.ts")
        XCTAssertTrue(result.context.contains("axios.get"))
    }
    func testMissingLabSaysWhichLabsExist() {
        XCTAssertTrue(ProjectCodeIndex(files: labFiles).search(question: "що ти робив у п'ятій лабі", active: nil).context.contains("WeatherService"))
        XCTAssertTrue(ProjectCodeIndex(files: labFiles).search(question: "що ти робив у п’ятій лабі", active: nil).context.contains("WeatherService"))
        let context = ProjectCodeIndex(files: overviewFiles).search(question: "що ти робив в 9 лабі", active: nil).context
        XCTAssertTrue(context.contains("lab-09"))
        XCTAssertTrue(context.contains("lab-06") && context.contains("lab-07"))
    }
    func testBigLabOverviewFitsTheBudgetAndKeepsEveryFile() {
        let files = (1...30).map { i in ProjectCodeFile(path: "lab-08/src/f\(i).ts", text: "export class Class\(i) {\n" + (1...40).map { "  method\($0)(): void {\n  }" }.joined(separator: "\n") + "\n}") }
        let result = ProjectCodeIndex(files: files).search(question: "що ти робив в 8 лабі", active: nil, budget: 4800)
        XCTAssertLessThanOrEqual(result.context.count, 4800)
        XCTAssertTrue(result.context.contains("Class1 ") && result.context.contains("Class30 "))
    }
    func testCodeAuthorRuleStaysOutOfTheGeneralPrompt() {
        XCTAssertTrue(CopilotSettings.codeAuthorRule.contains("від першої особи"))
        XCTAssertFalse(CopilotSettings.developerPrompt.contains(CopilotSettings.codeAuthorRule))
    }
    func testListenOnLaunchIsOptInAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 9]).write(to: store.url)
        XCTAssertFalse(try store.load().listenOnLaunch)
        var settings = try store.load(); settings.listenOnLaunch = true; try store.save(settings)
        XCTAssertTrue(try store.load().listenOnLaunch)
    }
    func testVisualQuestionsAreDetected() {
        for question in ["Що показує цей графік?", "Чому діаграма така?", "Опишіть гістограму", "Куди йде крива?", "Що це за лінія?", "Якого кольору стовпці?", "Що на осі X?", "Що в легенді?"] {
            XCTAssertTrue(VisualQuestionRouter.isVisual(question), question)
        }
        for question in ["Що таке дисперсія?", "Який код на цьому рядку?", "Чому код кривий?", "Як працює функція?"] {
            XCTAssertFalse(VisualQuestionRouter.isVisual(question), question)
        }
    }
    func testQuestionsAboutWhatIsOnScreenAreVisual() {
        for question in ["шо це за сині точки в тебе на екрані", "що ми бачимо на цій діаграмі, чому ці кульки різнокольорові", "Що ти бачиш?", "Що зображено на рисунку 7?", "Чому бульбашки різного розміру?"] {
            XCTAssertTrue(VisualQuestionRouter.isVisual(question), question)
        }
    }
    func testFullPromptSurvivesSmallBudget() {
        XCTAssertLessThanOrEqual(CopilotSettings.developerPrompt.count, 1400)
        let messages = SessionContext().messages(prompt: CopilotSettings.developerPrompt, history: [], question: "Що таке кеш?", code: "", topic: "", budget: 3200)
        XCTAssertEqual(messages[0].content, CopilotSettings.developerPrompt)
        XCTAssertTrue(messages[0].content.contains("не бачиш"))
    }
    func testFillersAndHangingWordsAreIncomplete() {
        for text in ["Що означають оці", "Чому ви взяли ці", "Розкажіть про", "Що ви отримали від", "Ну як воно, типу", "А ну"] { XCTAssertTrue(QuestionInbox.incomplete(text), text) }
        for text in ["Що це значить", "Чому саме ці?", "Що означає дисперсія"] { XCTAssertFalse(QuestionInbox.incomplete(text), text) }
    }
    func testShortPrepositionalTailJoinsPreviousQuestion() {
        var inbox = QuestionInbox(); let now = Date()
        inbox.observe("Що робить ця змінна", source: "S", utterance: UUID(), final: true, context: SessionContext(), at: now)
        inbox.observe("в 5 рядку?", source: "S", utterance: UUID(), final: true, context: SessionContext(), at: now.addingTimeInterval(1))
        XCTAssertEqual(inbox.entries.count, 1)
        XCTAssertEqual(inbox.entries[0].text, "Що робить ця змінна в 5 рядку?")
        inbox.observe("В чому різниця між ними?", source: "S", utterance: UUID(), final: true, context: SessionContext(), at: now.addingTimeInterval(2))
        XCTAssertEqual(inbox.entries.count, 2)
    }
    func testVagueReferenceWaitsLongerBeforeSettling() {
        var inbox = QuestionInbox(); let now = Date()
        inbox.observe("Що показує ця", source: "S", utterance: UUID(), final: true, context: SessionContext(), at: now)
        XCTAssertTrue(inbox.settle(at: now.addingTimeInterval(1.5)).isEmpty)
        XCTAssertEqual(inbox.settle(at: now.addingTimeInterval(2.7)).count, 1)
        var plain = QuestionInbox()
        plain.observe("Що таке кеш?", source: "S", utterance: UUID(), final: true, context: SessionContext(), at: now)
        XCTAssertEqual(plain.settle(at: now.addingTimeInterval(1.5)).count, 1)
    }
    func testAnyJetBrainsIDEMatchesExceptToolbox() {
        for id in ["com.jetbrains.WebStorm", "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce", "com.jetbrains.intellij"] { XCTAssertTrue(JetBrainsIDE.matches(id), id) }
        for id in ["com.jetbrains.toolbox", "com.microsoft.VSCode"] { XCTAssertFalse(JetBrainsIDE.matches(id), id) }
        XCTAssertFalse(JetBrainsIDE.matches(nil))
    }
    func testClaudeDefaultsUseHaikuAndNoKeyInSettings() throws {
        let settings = CopilotSettings()
        XCTAssertEqual(settings.answerBackend, "claude"); XCTAssertEqual(settings.backgroundBackend, "claude")
        XCTAssertEqual(settings.claudeModel, "claude-haiku-5-5"); XCTAssertFalse(settings.claudeSendScreenshots)
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(json.lowercased().contains("apikey")); XCTAssertFalse(json.contains("sk-ant"))
    }
    func testClaudeRequestBodyShape() throws {
        var settings = CopilotSettings(); settings.temperature = 0.3
        let messages = [ChatMessage(role: "system", content: "Правила"), ChatMessage(role: "user", content: "Раніше"), ChatMessage(role: "assistant", content: "Так"), ChatMessage(role: "user", content: "Питання")]
        let body = ClaudeRequest.body(messages: messages, settings: settings, images: ["QUJD"], formatJSON: false)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5"); XCTAssertEqual(body["system"] as? String, "Правила")
        XCTAssertEqual(body["stream"] as? Bool, true); XCTAssertEqual(body["max_tokens"] as? Int, 8192); XCTAssertNil(body["temperature"])
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        let turns = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(turns.count, 3); XCTAssertFalse(turns.contains { $0["role"] as? String == "system" })
        XCTAssertEqual(turns[0]["content"] as? String, "Раніше")
        let blocks = try XCTUnwrap(turns[2]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks[0]["type"] as? String, "image"); XCTAssertEqual(blocks[1]["text"] as? String, "Питання")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
        let classifier = ClaudeRequest.body(messages: messages, settings: settings, images: [], formatJSON: true)
        XCTAssertTrue((classifier["system"] as? String)?.contains("JSON") == true)
        XCTAssertEqual((classifier["output_config"] as? [String: String])?["effort"], "low")
    }
    func testClaudeStreamParsing() throws {
        var parser = ClaudeStreamParser()
        XCTAssertNil(try parser.parse("event: message_start"))
        XCTAssertNil(try parser.parse(#"data: {"type":"message_start","message":{"usage":{"input_tokens":120,"cache_read_input_tokens":5}}}"#))
        XCTAssertNil(try parser.parse(#"data: {"type":"ping"}"#))
        XCTAssertEqual(try parser.parse(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Привіт"}}"#)?.message?.content, "Привіт")
        XCTAssertEqual(parser.billableOutput, 2)
        XCTAssertEqual(try parser.parse(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"гм"}}"#)?.message?.thinking, "гм")
        XCTAssertNil(try parser.parse(#"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":40}}"#))
        let done = try XCTUnwrap(parser.parse(#"data: {"type":"message_stop"}"#))
        XCTAssertEqual(done.done, true); XCTAssertEqual(done.done_reason, "length")
        XCTAssertEqual(parser.inputTokens, 125); XCTAssertEqual(parser.billableOutput, 40); XCTAssertTrue(parser.finished)
    }
    func testClaudeStreamErrorsAndRefusalThrow() {
        var failing = ClaudeStreamParser()
        XCTAssertThrowsError(try failing.parse(#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        var refused = ClaudeStreamParser()
        XCTAssertNil(try refused.parse(#"data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":1}}"#))
        XCTAssertThrowsError(try refused.parse(#"data: {"type":"message_stop"}"#))
        XCTAssertTrue(ClaudeRequest.failure(status: 401, body: "").contains("ключ"))
        XCTAssertTrue(ClaudeRequest.failure(status: 400, body: #"{"error":{"message":"bad field"}}"#).contains("bad field"))
    }
    func testSpendLedgerPricesAndResetsDaily() {
        XCTAssertEqual(SpendLedger.cost(input: 100_000, output: 100_000), 0.06, accuracy: 1e-9)
        XCTAssertEqual(SpendLedger.cost(input: 200_000, output: 0), 0.10, accuracy: 1e-9) // large-prompt rate
        var ledger = SpendLedger()
        ledger.add(input: 100_000, output: 0, day: "2026-11-04"); ledger.add(input: 0, output: 100_000, day: "2026-11-04")
        XCTAssertEqual(ledger.spent(on: "2026-11-04"), 0.06, accuracy: 1e-9)
        XCTAssertEqual(ledger.spent(on: "2026-11-05"), 0)
        ledger.add(input: 100_000, output: 0, day: "2026-11-05")
        XCTAssertEqual(ledger.usd, 0.01, accuracy: 1e-9); XCTAssertEqual(ledger.outputTokens, 0)
    }
    func testClaudeServiceRefusesWithoutKeyOrOverLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = KeychainStore(service: "QuestionioTests-" + UUID().uuidString)
        defer { try? keychain.delete() }
        let spend = SpendTracker(url: directory.appendingPathComponent("spend.json"))
        let service = ClaudeService(keychain: keychain, spend: spend)
        var settings = CopilotSettings(); settings.claudeDailyLimitUSD = 0.05
        do { try await service.chat(messages: [ChatMessage(role: "user", content: "x")], settings: settings, images: [], formatJSON: false) { _ in }; XCTFail("Expected missing key") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Ключ Claude не задано")) }
        try keychain.save("test-key"); XCTAssertEqual(try keychain.read(), "test-key")
        try keychain.save("test-key-2"); XCTAssertEqual(try keychain.read(), "test-key-2")
        await spend.record(input: 1_000_000, output: 0)
        do { try await service.chat(messages: [ChatMessage(role: "user", content: "x")], settings: settings, images: [], formatJSON: false) { _ in }; XCTFail("Expected limit") }
        catch { XCTAssertTrue(error.localizedDescription.contains("денний ліміт")) }
        try keychain.delete(); XCTAssertNil(try keychain.read())
    }
    func testSavedSettingsWithoutEngineKeepWhisperAndParakeetPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 7, "language": "uk"]).write(to: store.url)
        XCTAssertEqual(try store.load().speechEngine, "whisper")
        var settings = try store.load(); settings.speechEngine = "parakeet"; try store.save(settings)
        XCTAssertEqual(try store.load().speechEngine, "parakeet")
    }
    func testEngineRouterFailsCleanlyWhenSelectedEngineIsNotLoaded() async {
        let router = SpeechEngineRouter(whisper: SpeechRecognitionService(), parakeet: ParakeetRecognitionService())
        await router.select(parakeet: true)
        do { _ = try await router.transcribe([0], language: "uk", vocabulary: ""); XCTFail("Expected not-loaded error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Parakeet is not loaded")) }
        await router.select(parakeet: false)
        do { _ = try await router.transcribe([0], language: "uk", vocabulary: ""); XCTFail("Expected not-loaded error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Whisper is not loaded")) }
    }
    func testMigrationPreservesCustomPrompt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["systemPrompt": "My own prompt"]).write(to: store.url)
        XCTAssertEqual(try store.load().systemPrompt, "My own prompt")
    }
    func testVADSilenceNeverCreatesChunks() {
        var buffer = AudioBufferManager(); let settings = CopilotSettings()
        for _ in 0..<400 { XCTAssertTrue(buffer.ingest(AudioFrame(samples: Array(repeating: 0, count: 1600), source: .system), settings: settings).isEmpty) }
        XCTAssertFalse(VoiceActivityDetector().isSpeech(Array(repeating: 0, count: 160)))
    }
    func testVADPauseFinalizesQuestion() {
        var buffer = AudioBufferManager(); var settings = CopilotSettings(); settings.silenceSeconds = 0.5
        let sound = AudioFrame(samples: Array(repeating: 0.03, count: 1600), source: .microphone)
        let silent = AudioFrame(samples: Array(repeating: 0, count: 1600), source: .microphone)
        var chunks: [AudioChunk] = []
        for _ in 0..<24 { chunks += buffer.ingest(sound, settings: settings) }
        for _ in 0..<6 { chunks += buffer.ingest(silent, settings: settings) }
        XCTAssertEqual(chunks.filter(\.final).count, 1); XCTAssertEqual(chunks.last?.source, .microphone)
        XCTAssertEqual(chunks.first?.utterance, chunks.last?.utterance)
    }
    func testChunkBoundAndOverlap() {
        var buffer = AudioBufferManager(); var settings = CopilotSettings(); settings.chunkSeconds = 4
        var chunks: [AudioChunk] = []
        for _ in 0..<160 { chunks += buffer.ingest(AudioFrame(samples: Array(repeating: 0.03, count: 1600), source: .system), settings: settings) }
        XCTAssertTrue(chunks.allSatisfy { $0.samples.count <= 64000 }); XCTAssertTrue(chunks.contains(where: \.overlapsPrevious))
    }
    func testPauseImmediatelyAfterFullChunkStillFinalizes() {
        var buffer = AudioBufferManager(); var settings = CopilotSettings(); settings.chunkSeconds = 4; settings.silenceSeconds = 0.5
        for _ in 0..<40 { _ = buffer.ingest(AudioFrame(samples: Array(repeating: 0.03, count: 1600), source: .system), settings: settings) }
        var chunks: [AudioChunk] = []
        for _ in 0..<6 { chunks += buffer.ingest(AudioFrame(samples: Array(repeating: 0, count: 1600), source: .system), settings: settings) }
        XCTAssertEqual(chunks.filter(\.final).count, 1)
    }
    func testStopImmediatelyAfterFullWindowFinalizesUtterance() {
        var buffer = AudioBufferManager(); var settings = CopilotSettings(); settings.chunkSeconds = 4
        var chunks: [AudioChunk] = []
        for _ in 0..<40 { chunks += buffer.ingest(AudioFrame(samples: Array(repeating: 0.03, count: 1600), source: .system), settings: settings) }
        XCTAssertTrue(chunks.contains { !$0.final })
        let final = buffer.flush(source: .system)
        XCTAssertEqual(final?.utterance, chunks.last?.utterance)
        XCTAssertTrue(final?.final == true)
    }
    func testLongDescriptionThenQuestionSurvivesChunkWindows() {
        var buffer = AudioBufferManager(); var settings = CopilotSettings(); settings.chunkSeconds = 4; settings.silenceSeconds = 0.8
        let sound = AudioFrame(samples: Array(repeating: 0.03, count: 1600), source: .system)
        let silent = AudioFrame(samples: Array(repeating: 0, count: 1600), source: .system)
        var chunks: [AudioChunk] = []
        for _ in 0..<120 { chunks += buffer.ingest(sound, settings: settings) }
        for _ in 0..<9 { chunks += buffer.ingest(silent, settings: settings) }
        XCTAssertGreaterThanOrEqual(chunks.filter { !$0.final }.count, 3)
        XCTAssertEqual(chunks.filter(\.final).count, 1)
        var assembler = TranscriptAssembler()
        let text = ["У мене є API який отримує вебхуки", "один вебхук може прийти кілька разів", "як забезпечити ідемпотентність при обробці", "при обробці"]
        var completed = ""
        for chunk in chunks {
            let phrase = text[min(chunk.window, text.count - 1)]
            completed = assembler.accept(phrase, chunk: chunk).completedUtterance ?? completed
        }
        XCTAssertTrue(completed.contains("У мене є API"))
        XCTAssertTrue(completed.contains("як забезпечити ідемпотентність"))
        XCTAssertTrue(QuestionDetectionService.isQuestion(completed))
        XCTAssertTrue(QuestionDetectionService.isQuestion("У мене є API який отримує вебхуки один і той самий вебхук може прийти двічі як забезпечити ідемпотентність при обробці"))
        XCTAssertFalse(QuestionDetectionService.isQuestion("Ми вже знаємо як працює цей механізм і описали всі його кроки"))
    }
    func testLongUtteranceFinalDecodeReplacesBrokenWindowText() {
        var buffer = AudioBufferManager(); var settings = CopilotSettings(); settings.chunkSeconds = 4; settings.silenceSeconds = 0.8
        let sound = AudioFrame(samples: Array(repeating: 0.03, count: 1600), source: .system)
        let silent = AudioFrame(samples: Array(repeating: 0, count: 1600), source: .system)
        var chunks: [AudioChunk] = []
        for _ in 0..<340 { chunks += buffer.ingest(sound, settings: settings) }
        for _ in 0..<9 { chunks += buffer.ingest(silent, settings: settings) }
        guard let final = chunks.last else { return XCTFail("Missing final decode") }
        XCTAssertTrue(final.final)
        XCTAssertTrue(final.replacesUtterance)
        XCTAssertGreaterThan(final.samples.count, 30 * 16000)
        var assembler = TranscriptAssembler()
        for chunk in chunks.dropLast() { _ = assembler.accept("Обривок веб-хука", chunk: chunk) }
        let corrected = "У нас є API який отримує вебхуки. Як забезпечити ідемпотентність якщо один вебхук прийде двічі?"
        let update = assembler.accept(corrected, chunk: final)
        XCTAssertEqual(update.confirmed, corrected)
        XCTAssertEqual(update.completedUtterance, corrected)
        XCTAssertTrue(QuestionDetectionService.isQuestion(corrected))
    }
    func testLongFinalDecodeKeepsEarlierWordsWhenWhisperReturnsBlank() {
        var assembler = TranscriptAssembler(); let id = UUID()
        _ = assembler.accept("Один вебхук може прийти двічі", chunk: chunk(id: id))
        let final = AudioChunk(samples: [], source: .system, final: true, utterance: id, window: 1, overlapsPrevious: false, replacesUtterance: true)
        let update = assembler.accept("", chunk: final)
        XCTAssertEqual(update.completedUtterance, "Один вебхук може прийти двічі")
        XCTAssertEqual(update.confirmed, "Один вебхук може прийти двічі")
    }
    func testDesiredOutcomeWithoutQuestionMarkTriggersAutomaticAnswer() {
        let heard = "У нас є API, який отримує веб-хуки. Один і той самий веб-хук може бути. Я хочу призвать обробку так, щоб у нас дані не задублювалися, навіть якщо буде працювати декілька років"
        XCTAssertTrue(QuestionDetectionService.isQuestion(heard))
        XCTAssertFalse(QuestionDetectionService.isQuestion("Я хочу обговорити наш API і показати його викладачу"))
    }
    func testSQLiteUnicodeAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try StorageManager(url: directory.appendingPathComponent("test.sqlite"))
        try await storage.save(session: UUID(), question: "Що таке 'SQL'?", answer: "Локальна відповідь 👋")
        let records = try await storage.records(); XCTAssertEqual(records.count, 1); XCTAssertEqual(records.first?.answer, "Локальна відповідь 👋")
        try await storage.deleteAll(); let empty = try await storage.records(); XCTAssertTrue(empty.isEmpty)
    }
    func testMissingWhisperFolderFailsOffline() async {
        let speech = SpeechRecognitionService()
        do { try await speech.load(folder: "/missing-localcopilot-model"); XCTFail("Expected offline error") } catch { XCTAssertTrue(error.localizedDescription.contains("Missing local")) }
    }
}
