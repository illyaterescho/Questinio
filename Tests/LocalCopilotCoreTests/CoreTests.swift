import XCTest
@testable import LocalCopilotCore
final class CoreTests: XCTestCase {
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
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-05/demo.ts", text: "const selected = weather.find(city => city.id);"), ProjectCodeFile(path: "lab-06/demo.ts", text: "const selected = weather.find(city => city.id);")])
        XCTAssertNil(index.matchVisible(source: "WebStorm demo.ts", visible: "const selected = weather.find(city => city.id);"))
        XCTAssertEqual(index.search(question: "Лаба 6 demo.ts рядок 1", active: nil).files, ["lab-06/demo.ts"])
        XCTAssertTrue(index.search(question: "рядок 129", active: nil).context.contains("Уточни"))
    }
    func testCodeLineAliasesAndOutOfRange() {
        for question in ["в 129 строці", "на рядку 129", "line 129", "129-му рядку"] { XCTAssertEqual(ProjectCodeIndex.requestedLine(question), 129, question) }
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "a.ts", text: "const a = 1;")])
        XCTAssertTrue(index.search(question: "рядок 129", active: "a.ts").context.contains("рядка 129 немає"))
    }
    func testProjectWideSearchPrioritizesStorageOverActiveDashboard() {
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-06/weather-dashboard.component.ts", text: "favorites = this.favoritesStorage.load(); refreshSavedFavorites() { this.favoritesStorage.save(this.favorites); }"), ProjectCodeFile(path: "lab-06/services/favorites-storage.service.ts", text: "class FavoritesStorageService { save(items) { localStorage.setItem(key, JSON.stringify(items)); } load() { return JSON.parse(localStorage.getItem(key)); } }")])
        let result = index.search(question: "Де у лабі 6 зберігається вибране після перезавантаження?", active: "lab-06/weather-dashboard.component.ts")
        XCTAssertEqual(result.files.first, "lab-06/services/favorites-storage.service.ts")
    }
    func testCurrentFunctionUsesActiveFileAndCursorWithoutLabNumber() {
        let body = (1...150).map { number in number == 87 ? "function calculateTotal() { return prices.reduce((a, b) => a + b, 0); }" : "const item\(number) = \(number);" }.joined(separator: "\n")
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "lab-03/source.ts", text: body), ProjectCodeFile(path: "lab-06/other.ts", text: "function other() {}")])
        let result = index.search(question: "Що робить ця функція тут?", active: "lab-03/source.ts", focusLine: 87, focusedSymbol: "calculateTotal(), function")
        XCTAssertEqual(result.files, ["lab-03/source.ts"])
        XCTAssertTrue(result.context.contains("87: function calculateTotal()"))
        XCTAssertTrue(result.context.contains("Активний символ WebStorm: calculateTotal()"))
        XCTAssertFalse(result.context.contains("\n1: const item1"))
    }
    func testNamedFunctionOverridesCursorInOpenFile() {
        let body = (1...250).map { number in number == 129 ? "function getWorkerByID(id: number) { return workers.find(worker => worker.id === id); }" : "const unrelatedItem\(number) = \(number);" }.joined(separator: "\n")
        let path = "lab-01/src/app/workers.ts"
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: path, text: body)])
        let question = "Що робить getWorkerByID у відкритому файлі?"
        XCTAssertFalse(ProjectCodeIndex.refersToCurrentCode(question))
        let result = index.search(question: question, active: path, focusLine: 1, focusedSymbol: "unrelatedItem1")
        XCTAssertEqual(result.files, [path])
        XCTAssertTrue(result.context.contains("129: function getWorkerByID"))
        XCTAssertFalse(result.context.contains("Активний символ WebStorm: unrelatedItem1"))
    }
    func testDirectFunctionQuestionUsesDefinitionInsteadOfCallSites() {
        let index = ProjectCodeIndex(files: [
            ProjectCodeFile(path: "src/app/lab-01.ts", text: "import { getWorkerByID } from './workers';\nconst worker = getWorkerByID(0);"),
            ProjectCodeFile(path: "src/app/workers.ts", text: "export function getWorkerByID(id: number): Worker | undefined {\n  if (id <= 0) return undefined;\n  return workers.find(worker => worker.id === id);\n}")
        ])
        let result = index.search(question: "Де визначено getWorkerByID і що повертає при id = 0?", active: nil, budget: 2400)
        XCTAssertEqual(result.files, ["src/app/workers.ts"])
        XCTAssertTrue(result.context.contains("id <= 0"))
    }
    func testCodeSymbolSearchAndBudget() {
        let index = ProjectCodeIndex(files: [ProjectCodeFile(path: "favorites.ts", text: "function persistFavorites() { storage.save(items); }"), ProjectCodeFile(path: "weather.ts", text: "function getWeather() { return []; }")])
        let result = index.search(question: "Де збереження вибраного?", active: nil, budget: 1000)
        XCTAssertEqual(result.files.first, "favorites.ts"); XCTAssertLessThan(result.context.count, 1000)
    }
    func testCodeQuestionsRouteOnlyWhenProjectContextIsRelevant() {
        for question in ["А що у вас значить цей метод?", "Ось 197 строка, що вона робить?", "Де в коді зберігається вибране?", "Що робить getWorkerByID?", "Де у лабі 6 визначено сервіс?", "Що в такій-то строці?"] {
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
        let original = ProjectCodeIndex(files: [ProjectCodeFile(path: "src/app/workers.ts", text: "function oldValue() { return 1; }")], rootName: "lab-01")
        let updated = original.replacing(path: "src/app/workers.ts", text: "function newValue() { return 2; }")
        XCTAssertEqual(updated.search(question: "Що у лабі 1 в рядку 1?", active: nil).files, ["src/app/workers.ts"])
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
        for text in ["Чому", "Ну а як", "Так, а що тут", "Добре. Поясніть", "Шо таке проміс", "Статична типізація", "Рейс кондишин", "А getWorkerByID", "Що тут означає save()"] {
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
        XCTAssertTrue(QuestionContextRouter.isSelfContained("Що робить getWorkerByID?"))
        XCTAssertFalse(QuestionContextRouter.isSelfContained("А чому він повертає undefined?"))
        XCTAssertFalse(QuestionContextRouter.isSelfContained("Що робить ця функція тут?"))
        let messages = context.messages(prompt: "Відповідай коротко", history: [], question: "Що робить getWorkerByID?", code: "63: function getWorkerByID() { return undefined; }", topic: "Стара тема", budget: 3200, includeConversation: false)
        XCTAssertTrue(messages.last!.content.contains("63: function getWorkerByID"))
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
    func testLegacySettingsMigrateWithoutLosingAudioOrModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        let old: [String: Any] = ["model": "qwen3.5:4b", "modelPath": "/local/whisper", "language": "uk", "maxTokens": 256, "audioMode": "Both", "systemPrompt": "Ти — локальний помічник для навчання старий текст"]
        try JSONSerialization.data(withJSONObject: old).write(to: store.url)
        let migrated = try store.load()
        XCTAssertEqual(migrated.maxTokens, -1); XCTAssertTrue(migrated.autoLoadWhisper)
        XCTAssertEqual(migrated.modelPath, "/local/whisper"); XCTAssertEqual(migrated.audioMode, .both)
        XCTAssertEqual(migrated.model, "qwen3.5:4b"); XCTAssertEqual(migrated.language, "uk")
        XCTAssertEqual(migrated.systemPrompt, CopilotSettings.developerPrompt)
        try store.save(migrated); XCTAssertEqual(try store.load(), migrated)
    }
    func testMigrationPreservesCustomPrompt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["systemPrompt": "My own prompt"]).write(to: store.url)
        XCTAssertEqual(try store.load().systemPrompt, "My own prompt")
    }
    func testVersionTwoPromptMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        for prompt in [CopilotSettings.legacyDeveloperPrompt, "My custom concise prompt"] {
            try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "systemPrompt": prompt, "applicationID": "com.apple.QuickTimePlayerX", "microphoneID": 100, "maxTokens": -1]).write(to: store.url)
            let result = try store.load()
            XCTAssertEqual(result.schemaVersion, 7)
            XCTAssertEqual(result.systemPrompt, prompt == CopilotSettings.legacyDeveloperPrompt ? CopilotSettings.developerPrompt : prompt)
            XCTAssertEqual(result.applicationID, "com.apple.QuickTimePlayerX"); XCTAssertEqual(result.microphoneID, 100); XCTAssertEqual(result.maxTokens, -1)
        }
    }
    func testVersionThreePromptMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        for prompt in [CopilotSettings.legacyConcisePrompt, "My custom prompt v3"] {
            try JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "systemPrompt": prompt]).write(to: store.url)
            let result = try store.load()
            XCTAssertEqual(result.schemaVersion, 7)
            XCTAssertEqual(result.systemPrompt, prompt == CopilotSettings.legacyConcisePrompt ? CopilotSettings.developerPrompt : prompt)
        }
    }
    func testVersionSixLoadsInstalledWhisperAtLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 5, "autoLoadWhisper": false, "whisperVariant": "openai_whisper-small", "modelPath": "/tmp/openai_whisper-large-v3-v20240930_turbo", "model": "qwen3.5:9b"]).write(to: store.url)
        let result = try store.load()
        XCTAssertEqual(result.schemaVersion, 7)
        XCTAssertTrue(result.autoLoadWhisper)
        XCTAssertEqual(result.whisperVariant, "openai_whisper-large-v3-v20240930_turbo")
        XCTAssertEqual(result.model, "qwen3.5:9b")
    }
    func testVersionSevenUpdatesOnlyDefaultPrompt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsManager(url: directory.appendingPathComponent("settings.json"))
        let previous = CopilotSettings.developerPrompt.replacingOccurrences(of: " Не називай callback суто синхронним або суто асинхронним: спосіб виклику визначає код, що його приймає.", with: "")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 6, "systemPrompt": previous]).write(to: store.url)
        XCTAssertEqual(try store.load().systemPrompt, CopilotSettings.developerPrompt)
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 6, "systemPrompt": "Мій власний стиль"]).write(to: store.url)
        XCTAssertEqual(try store.load().systemPrompt, "Мій власний стиль")
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
