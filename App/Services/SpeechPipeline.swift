import Foundation
import LocalCopilotCore

struct PipelineEvent: Sendable {
    var source: AudioSource
    var update: TranscriptUpdate?
    var level: Float?
    var seconds: Double?
    var error: String?
    var question: String?
    var finalAudioSeconds: Double?
    var wholeUtteranceDecode: Bool?
}
actor SpeechPipeline {
    private let speech: SpeechRecognitionService
    private var buffers: [AudioSource: AudioBufferBox] = [:]
    private var assemblers: [AudioSource: TranscriptAssembler] = [:]
    private var detector = QuestionDetectionService()
    private var pending: [AudioChunk] = []
    private var fullDecodeFallback: [UUID: [AudioChunk]] = [:]
    private var microphoneMuted = false
    private var microphoneEpoch = UUID()
    func setMicrophoneMuted(_ muted: Bool) {
        microphoneMuted = muted; microphoneEpoch = UUID()
        buffers[.microphone] = nil; assemblers[.microphone] = nil; lastFrames[.microphone] = nil
        pending.removeAll { $0.source == .microphone }
    }
    private var decoding = false
    private var decodeTask: Task<Void, Never>?
    private var running = false
    private var epoch = UUID()
    private var lastFrames: [AudioSource: Date] = [:]
    private var lastLevelEvent: [AudioSource: Date] = [:]
    private var settings = CopilotSettings()
    private var contextVocabulary = ""
    func setContextVocabulary(_ terms: String) { contextVocabulary = String(terms.prefix(900)) }
    private var handler: (@Sendable (PipelineEvent) async -> Void)?
    init(speech: SpeechRecognitionService) { self.speech = speech }
    func run(frames: AsyncStream<AudioFrame>, settings: CopilotSettings, handler: @escaping @Sendable (PipelineEvent) async -> Void) async {
        self.settings = settings; self.handler = handler; running = true
        microphoneMuted = false; microphoneEpoch = UUID()
        buffers = [:]; assemblers = [:]; detector = QuestionDetectionService(); pending = []; fullDecodeFallback = [:]; epoch = UUID()
        lastFrames = [:]; lastLevelEvent = [:]
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    await self.tick()
                }
            }
            for await frame in frames {
                if Task.isCancelled || !running { break }
                lastFrames[frame.source] = Date()
                await ingest(frame)
            }
            group.cancelAll()
        }
        if Task.isCancelled { cancel() }
        else { await finishPendingAudio() }
    }
    private func ingest(_ frame: AudioFrame) async {
        let now = Date()
        if now.timeIntervalSince(lastLevelEvent[frame.source] ?? .distantPast) >= 0.1 {
            lastLevelEvent[frame.source] = now
            await handler?(PipelineEvent(source: frame.source, level: VoiceActivityDetector.rms(frame.samples)))
        }
        guard frame.source != .microphone || !microphoneMuted else { return }
        let buffer = buffers[frame.source] ?? AudioBufferBox()
        buffers[frame.source] = buffer
        let chunks = buffer.value.ingest(frame, settings: settings)
        for chunk in chunks { await enqueue(chunk) }
    }
    private func tick() async {
        guard running else { return }
        // ScreenCaptureKit may stop emitting samples during silence. Advance VAD
        // with zero padding after a real source goes idle, so its utterance closes.
        for (source, time) in lastFrames where Date().timeIntervalSince(time) > 0.15 {
            await ingest(AudioFrame(samples: [Float](repeating: 0, count: 1600), source: source))
        }
    }
    func discontinuity() {
        buffers = [:]; pending = []; fullDecodeFallback = [:]; epoch = UUID()
        for source in Array(assemblers.keys) { assemblers[source]?.discontinuity() }
    }
    func cancel() {
        running = false; pending = []; fullDecodeFallback = [:]; buffers = [:]; epoch = UUID()
        decodeTask?.cancel(); decodeTask = nil
    }
    private func finishPendingAudio() async {
        guard running else { return }
        // A user may press Stop after the speaker pauses while Whisper is still
        // decoding earlier windows. Finish the last window and drain in order.
        for (source, buffer) in buffers {
            if let chunk = buffer.value.flush(source: source) { await enqueue(chunk) }
        }
        if let decodeTask { await decodeTask.value }
        running = false; pending = []; fullDecodeFallback = [:]; buffers = [:]; handler = nil
    }
    private func enqueue(_ chunk: AudioChunk) async {
        if chunk.replacesUtterance {
            // The complete utterance supersedes queued six-second windows.
            // Prioritize it so a long question does not wait behind every
            // redundant preview; preserve the windows if this decode is blank.
            let old = pending.filter { $0.utterance == chunk.utterance }
            pending.removeAll { $0.utterance == chunk.utterance }
            var fallback = old
            if let samples = chunk.fallbackSamples {
                fallback.append(AudioChunk(samples: samples, source: chunk.source, final: true, utterance: chunk.utterance,
                                           window: chunk.window, overlapsPrevious: chunk.window > 0))
            }
            fullDecodeFallback[chunk.utterance] = fallback
            pending.insert(chunk, at: 0)
            if !decoding { decoding = true; decodeTask = Task { await self.drain() } }
            return
        }
        // Coalesce interim snapshots of the same window; retain final results.
        pending.removeAll { $0.utterance == chunk.utterance && $0.window == chunk.window && !$0.final }
        if pending.count >= 8 {
            // A final window carries unique words from a long question. Only
            // provisional previews may be discarded under decoder pressure.
            if let preview = pending.firstIndex(where: { !$0.final }) {
                pending.remove(at: preview)
            } else if !chunk.final {
                return
            }
        }
        pending.append(chunk)
        if !decoding { decoding = true; decodeTask = Task { await self.drain() } }
    }
    private func drain() async {
        defer { decoding = false; decodeTask = nil }
        while !pending.isEmpty && running {
            let chunk = pending.removeFirst(); let currentEpoch = epoch; let micEpoch = microphoneEpoch
            do {
                let result = try await speech.transcribe(chunk.samples, language: settings.language, vocabulary: settings.speechVocabulary + " " + contextVocabulary)
                guard running, currentEpoch == epoch, chunk.source != .microphone || (!microphoneMuted && micEpoch == microphoneEpoch) else { continue }
                if chunk.replacesUtterance {
                    let fallback = fullDecodeFallback.removeValue(forKey: chunk.utterance) ?? []
                    if result.text.split(whereSeparator: \.isWhitespace).count < 3 && !fallback.isEmpty {
                        pending.insert(contentsOf: fallback, at: 0)
                        continue
                    }
                }
                var assembler = assemblers[chunk.source] ?? TranscriptAssembler()
                let update = assembler.accept(result.text, chunk: chunk); assemblers[chunk.source] = assembler
                var question: String?
                if let completed = update.completedUtterance, chunk.source == .system || settings.answerFromMicrophone {
                    question = detector.completed(completed)
                }
                await handler?(PipelineEvent(source: chunk.source, update: update, seconds: result.seconds, question: question,
                                             finalAudioSeconds: chunk.final ? Double(chunk.samples.count) / 16000 : nil,
                                             wholeUtteranceDecode: chunk.final ? chunk.replacesUtterance : nil))
            } catch {
                guard running, currentEpoch == epoch, chunk.source != .microphone || (!microphoneMuted && micEpoch == microphoneEpoch) else { continue }
                if chunk.replacesUtterance, let fallback = fullDecodeFallback.removeValue(forKey: chunk.utterance), !fallback.isEmpty {
                    pending.insert(contentsOf: fallback, at: 0)
                    continue
                }
                await handler?(PipelineEvent(source: chunk.source, error: error.localizedDescription))
            }
        }
    }
}

private final class AudioBufferBox {
    var value = AudioBufferManager()
}
