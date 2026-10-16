import XCTest
@testable import LocalCopilotCore

final class DialogueReliabilityTests: XCTestCase {
    let teacher = "Співрозмовник"
    func testManualQuestionDoesNotTriggerAnotherAutomaticAnswer() {
        var inbox = QuestionInbox(); let t = Date()
        inbox.append("Що означає ексцес?", source: "Введено вручну", context: SessionContext(), at: t)
        XCTAssertEqual(inbox.entries.count, 1)
        XCTAssertTrue(inbox.settle(at: t.addingTimeInterval(3)).isEmpty)
    }
    func testPauseAndStudentReplyDoNotEndIncompleteTeacherQuestion() {
        var inbox = QuestionInbox(); var context = SessionContext(); let t = Date()
        context.append(speaker: teacher, text: "Обговорюємо незміщену дисперсію.")
        inbox.observe("Чому ми ділимо на", source: teacher, utterance: UUID(), final: true, context: context, at: t)
        XCTAssertTrue(inbox.settle(at: t.addingTimeInterval(3)).isEmpty)
        inbox.observe("Я зараз покажу формулу", source: "Мікрофон", utterance: UUID(), final: true, context: context, at: t.addingTimeInterval(3))
        inbox.observe("ен мінус один при оцінюванні дисперсії", source: teacher, utterance: UUID(), final: true, context: context, at: t.addingTimeInterval(4))
        let ready = inbox.settle(at: t.addingTimeInterval(6))
        XCTAssertEqual(ready.count, 1)
        XCTAssertTrue(ready[0].text.contains("ділимо на ен мінус один"))
        XCTAssertTrue(ready[0].context.recent.contains("незміщену"))
        XCTAssertTrue(inbox.settle(at: t.addingTimeInterval(8)).isEmpty)
    }
    func testSpeakerAbandonsQuestionInsideSameUtterance() {
        var inbox = QuestionInbox(); let t = Date(); let utterance = UUID(); let context = SessionContext()
        inbox.observe("Чому у формулі ділимо на", source: teacher, utterance: utterance, final: false, context: context, at: t)
        let old = inbox.entries[0]
        inbox.observe("Чому у формулі ділимо на, стоп, краще чому 72 та 63 залишили?", source: teacher, utterance: utterance, final: true, context: context, at: t.addingTimeInterval(2))
        let ready = inbox.settle(at: t.addingTimeInterval(4))
        XCTAssertEqual(inbox.entries.count, 2)
        XCTAssertEqual(inbox.entries[0].state, .interrupted)
        XCTAssertFalse(inbox.isCurrent(old.id, revision: old.revision))
        XCTAssertEqual(ready.count, 1)
        XCTAssertTrue(ready[0].text.hasPrefix("чому 72"))
        XCTAssertFalse(ready[0].text.contains("ділимо"))
    }
    func testReformulationKeepsOldQuestionAndInvalidatesAutomaticAnswer() {
        var inbox = QuestionInbox(); let t = Date(); let context = SessionContext()
        inbox.observe("Чому використали середнє?", source: teacher, utterance: UUID(), final: true, context: context, at: t)
        let old = inbox.settle(at: t.addingTimeInterval(2))[0]
        inbox.observe("Ні, точніше, чому не використали медіану?", source: teacher, utterance: UUID(), final: true, context: context, at: t.addingTimeInterval(3))
        let new = inbox.settle(at: t.addingTimeInterval(5))[0]
        XCTAssertEqual(inbox.entries[0].state, .superseded)
        XCTAssertEqual(new.supersedes, old.id)
        XCTAssertFalse(inbox.isCurrent(old.id, revision: old.revision))
        XCTAssertTrue(new.text.contains("медіану"))
    }
    func testFinalOnlyReplayKeepsInterruptedHeadAndDoesNotDuplicateReplacement() {
        var inbox = QuestionInbox(); let t = Date(); let id = UUID(); let context = SessionContext()
        let text = "Чому ми ділимо на, стоп, краще поясніть ексцес?"
        inbox.observe(text, source: teacher, utterance: id, final: false, context: context, at: t)
        inbox.observe(text, source: teacher, utterance: id, final: true, context: context, at: t.addingTimeInterval(1))
        let ready = inbox.settle(at: t.addingTimeInterval(3))
        XCTAssertEqual(inbox.entries.count, 2)
        XCTAssertEqual(inbox.entries[0].state, .interrupted)
        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready[0].supersedes, inbox.entries[0].id)
    }
    func testOrdinaryClarificationAndStopCriterionAreNotCancellation() {
        var inbox = QuestionInbox(); let t = Date(); let context = SessionContext()
        inbox.observe("Що таке стоп-критерій?", source: teacher, utterance: UUID(), final: true, context: context, at: t)
        _ = inbox.settle(at: t.addingTimeInterval(2))
        inbox.observe("Це математичне сподівання, точніше оцінка середнього.", source: teacher, utterance: UUID(), final: true, context: context, at: t.addingTimeInterval(3))
        XCTAssertEqual(inbox.entries.count, 1)
        XCTAssertEqual(inbox.entries[0].state, .ready)
    }
    func testSemanticDecisionCannotInventTranscriptAndDoesNotMergeOtherSpeaker() throws {
        var inbox = QuestionInbox(); let t = Date(); let context = SessionContext()
        inbox.append("Що означає дисперсія?", source: teacher, context: context, at: t)
        let decision = try DialogueIntentDecision.parse(#"{"action":"replace","evidence":"Довірчий інтервал"}"#)
        inbox.applyIntent(decision, text: "Я відповів", source: "Мікрофон", utterance: UUID(), context: context, at: t.addingTimeInterval(3))
        XCTAssertEqual(inbox.entries.count, 1)
        XCTAssertEqual(inbox.entries[0].state, .ready)
        XCTAssertThrowsError(try DialogueIntentDecision.parse(#"{"action":"run_shell","evidence":"x"}"#))
    }
    func testFortyFiveMinuteTextJournalRetainsBeginningAndRecoversTruncatedTail() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SessionJournal(directory: directory); let session = UUID(); let start = Date()
        var context = SessionContext(); var inbox = QuestionInbox()
        for i in 0..<450 {
            let text = i == 0 ? "На початку захисту аптеки залишили 72 та 63 як реальний попит." : i % 3 == 0 ? "Що означає дисперсія у прикладі номер \(i)?" : "Розглядаємо формули та статистичні властивості вибірки номер \(i)."
            let item = DialogueRecord(date: start.addingTimeInterval(Double(i * 6)), source: teacher, text: text)
            context.append(speaker: teacher, text: text)
            inbox.observe(text, source: teacher, utterance: item.id, final: true, context: context, at: item.date)
            _ = inbox.settle(at: item.date.addingTimeInterval(2))
            try await journal.append(item, session: session)
        }
        let records = try await journal.records(session: session)
        XCTAssertEqual(records.count, 450)
        XCTAssertFalse(context.recent.contains("На початку захисту"))
        XCTAssertEqual(inbox.entries.count, 149)
        XCTAssertTrue(inbox.entries.allSatisfy { $0.context.recent.count <= 11000 })
        let found = try await journal.relevant(question: "Чому залишили 72 і 63?", session: session)
        XCTAssertTrue(found.contains("реальний попит"))
        let path = await journal.url(session: session)
        let file = try FileHandle(forWritingTo: path); try file.seekToEnd(); try file.write(contentsOf: Data("{\"truncated\":".utf8)); try file.close()
        let recovered = try await journal.records(session: session)
        XCTAssertEqual(recovered.count, 450)
        try await journal.append(DialogueRecord(source: teacher, text: "Продовження після відновлення"), session: session)
        let resumed = try await journal.records(session: session)
        XCTAssertEqual(resumed.count, 451)
        XCTAssertTrue(SessionJournal.export(recovered).contains("На початку захисту"))
        try await journal.append(DialogueRecord(date: start.addingTimeInterval(5000), source: teacher, text: "72 — майбутня зміна умови"), session: session)
        let earlier = try await journal.relevant(question: "72", session: session, before: start.addingTimeInterval(3000))
        XCTAssertFalse(earlier.contains("майбутня"))
        print("45-minute dialogue: 450 final turns; 149 questions; beginning recovered; no future context")
    }
    func testOverflowAudioRoundTripAndPrivateFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = (0..<4000).map { Float($0) / 4000 }; let id = UUID()
        var item: QueuedAudioChunk? = QueuedAudioChunk(AudioChunk(samples: samples, source: .system, final: true, utterance: id, window: 3, overlapsPrevious: false, replacesUtterance: true, fallbackSamples: Array(samples.suffix(100))))
        try item!.spill(to: directory)
        XCTAssertEqual(item!.residentSampleCount, 0)
        let result = try item!.load()
        XCTAssertEqual(result.samples, samples); XCTAssertEqual(result.utterance, id)
        XCTAssertEqual(result.fallbackSamples, Array(samples.suffix(100)))
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        item = nil
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }
    func testFortyFiveMinutesOfDualSourceAudioWithInjectedDecoder() async {
        let collector = PipelineCollector()
        let pipeline = SpeechPipeline(transcribe: { samples, _, _ in
            let peak = samples.max() ?? 0
            return SpeechResult(text: peak > 0.05 ? "Я пояснюю формулу дисперсії." : "Що означає дисперсія?", seconds: 0.001)
        })
        let stream = AsyncStream<AudioFrame> { output in
            let teacherSamples = [Float](repeating: 0.03, count: 1600)
            let studentSamples = [Float](repeating: 0.06, count: 1600)
            let silence = [Float](repeating: 0, count: 1600)
            for _ in 0..<300 {
                for step in 0..<90 {
                    output.yield(AudioFrame(samples: step < 23 ? teacherSamples : silence, source: .system))
                    output.yield(AudioFrame(samples: (40..<63).contains(step) ? studentSamples : silence, source: .microphone))
                }
            }
            output.finish()
        }
        await pipeline.run(frames: stream, settings: CopilotSettings()) { event in await collector.add(event) }
        let finals = await collector.finals
        XCTAssertEqual(finals.filter { $0.source == .system }.count, 300)
        XCTAssertEqual(finals.filter { $0.source == .microphone }.count, 300)
        XCTAssertTrue(finals.filter { $0.source == .system }.allSatisfy { $0.update?.completedUtterance == "Що означає дисперсія?" })
        XCTAssertTrue(finals.filter { $0.source == .microphone }.allSatisfy { $0.update?.completedUtterance == "Я пояснюю формулу дисперсії." })
        let errors = await collector.errors
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        let metrics = await pipeline.statistics()
        XCTAssertEqual(metrics.receivedSamples, 2 * 2700 * 16000)
        XCTAssertEqual(metrics.completedUtterances, 600)
        print("45-minute virtual PCM: 54,000 source frames; 600/600 final utterances; decoder injected, not Whisper or live devices")
    }
    func testStalledDecoderSpoolsWithoutDroppingUniqueSpeech() async {
        let gate = DecoderGate(); let collector = PipelineCollector()
        let pipeline = SpeechPipeline(transcribe: { _, _, _ in
            await gate.waitOnce()
            return SpeechResult(text: "Що означає дисперсія?", seconds: 0.01)
        })
        let stream = AsyncStream<AudioFrame> { output in
            let sound = [Float](repeating: 0.03, count: 1600); let quiet = [Float](repeating: 0, count: 1600)
            for _ in 0..<80 { for step in 0..<90 { output.yield(AudioFrame(samples: step < 23 ? sound : quiet, source: .system)) } }
            output.finish()
        }
        let task = Task { await pipeline.run(frames: stream, settings: CopilotSettings()) { event in await collector.add(event) } }
        for _ in 0..<10000 {
            if await pipeline.statistics().receivedSamples == 720 * 16000 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        await gate.release()
        await task.value
        let metrics = await pipeline.statistics()
        XCTAssertEqual(metrics.completedUtterances, 80)
        XCTAssertGreaterThan(metrics.spilledChunks, 0)
        XCTAssertLessThanOrEqual(metrics.peakResidentQueuedSamples, 90 * 16000)
        XCTAssertEqual(metrics.cacheFiles, 0)
    }
    func testStopFlushesSpeechAndDecoderFailureDoesNotKillNextUtterance() async {
        let calls = DecodeAttempts(); let collector = PipelineCollector()
        let pipeline = SpeechPipeline(transcribe: { _, _, _ in
            let count = await calls.next()
            if count == 1 { throw CopilotError.message("Injected transient decoder failure") }
            return SpeechResult(text: "Що означає ексцес?", seconds: 0.001)
        })
        let stream = AsyncStream<AudioFrame> { output in
            let sound = [Float](repeating: 0.03, count: 1600)
            let quiet = [Float](repeating: 0, count: 1600)
            for _ in 0..<16 { output.yield(AudioFrame(samples: sound, source: .system)) }
            for _ in 0..<10 { output.yield(AudioFrame(samples: quiet, source: .system)) }
            for _ in 0..<16 { output.yield(AudioFrame(samples: sound, source: .system)) }
            output.finish() // Stop without trailing silence must still finalize.
        }
        await pipeline.run(frames: stream, settings: CopilotSettings()) { event in await collector.add(event) }
        let finals = await collector.finals
        XCTAssertFalse(finals.isEmpty)
        XCTAssertEqual(finals.last?.update?.completedUtterance, "Що означає ексцес?")
        let metrics = await pipeline.statistics()
        XCTAssertEqual(metrics.decoderRetries, 1)
        XCTAssertEqual(finals.count, 2)
    }
    func testOverloadedLongUtteranceKeepsEveryCommittedWindow() async {
        let gate = DecoderGate(); let collector = PipelineCollector()
        let pipeline = SpeechPipeline(transcribe: { samples, _, _ in
            await gate.waitOnce()
            let marker = Int(((samples.max() ?? 0) * 10000).rounded())
            return SpeechResult(text: "маркер\(marker)", seconds: 0.01)
        })
        var settings = CopilotSettings(); settings.chunkSeconds = 4
        var expected = Set<String>(); var buffer = AudioBufferManager()
        let frames = (0..<800).map { i in AudioFrame(samples: [Float](repeating: 0.03 + Float(i / 35) / 1000, count: 1600), source: .system) }
        for frame in frames {
            for chunk in buffer.ingest(frame, settings: settings) where !chunk.isPreview {
                expected.insert("маркер\(Int(((chunk.samples.max() ?? 0) * 10000).rounded()))")
            }
        }
        let stream = AsyncStream<AudioFrame> { output in frames.forEach { output.yield($0) }; output.finish() }
        let options = settings
        let task = Task { await pipeline.run(frames: stream, settings: options) { event in await collector.add(event) } }
        for _ in 0..<3000 {
            if await pipeline.statistics().receivedSamples == 80 * 16000 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        await gate.release(); await task.value
        let final = await collector.finals.last?.update?.completedUtterance ?? ""
        for marker in expected { XCTAssertTrue(final.contains(marker), "Missing unique window: \(marker)") }
        let metrics = await pipeline.statistics()
        XCTAssertEqual(metrics.completedUtterances, 1)
    }
}

private actor PipelineCollector {
    var finals: [PipelineEvent] = []
    var errors: [String] = []
    func add(_ event: PipelineEvent) {
        if event.update?.completedUtterance != nil { finals.append(event) }
        if let error = event.error { errors.append(error) }
    }
}
private actor DecodeAttempts { var count = 0; func next() -> Int { count += 1; return count } }
private actor DecoderGate {
    var first = true; var opened = false; var continuation: CheckedContinuation<Void, Never>?
    func waitOnce() async {
        guard first else { return }; first = false
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { opened = true; continuation?.resume(); continuation = nil }
}
