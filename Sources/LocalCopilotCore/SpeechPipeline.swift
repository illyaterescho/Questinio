import Foundation

public struct PipelineEvent: Sendable {
    public var source: AudioSource
    public var update: TranscriptUpdate?
    public var level: Float?
    public var seconds: Double?
    public var error: String?
    public var question: String?
    public var finalAudioSeconds: Double?
    public var wholeUtteranceDecode: Bool?
    public var utterance: UUID?
    public var capturedAt: Date?
    public var pendingSeconds: Double?
    public var fatal: Bool?
    public var recognitionGap: Bool?
}
public struct SpeechPipelineStatistics: Sendable {
    public var receivedSamples = 0
    public var completedUtterances = 0
    public var spilledChunks = 0
    public var peakResidentQueuedSamples = 0
    public var peakQueueSeconds = 0.0
    public var decoderRetries = 0
    public var cacheFiles = 0
}
public actor SpeechPipeline {
    private var metrics = SpeechPipelineStatistics()
    public func statistics() -> SpeechPipelineStatistics {
        var copy = metrics
        copy.cacheFiles = (try? FileManager.default.contentsOfDirectory(atPath: spoolDirectory.path).count) ?? 0
        return copy
    }
    private let transcribe: @Sendable ([Float], String, String) async throws -> SpeechResult
    private var buffers: [AudioSource: AudioBufferBox] = [:]
    private var assemblers: [AudioSource: TranscriptAssembler] = [:]
    private var detector = QuestionDetectionService()
    private var pending: [QueuedAudioChunk] = []
    private var fullDecodeFallback: [UUID: [QueuedAudioChunk]] = [:]
    private let spoolDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("questionio-speech-" + UUID().uuidString)
    private var queueWarningAt = Date.distantPast
    private var microphoneMuted = false
    private var microphoneEpoch = UUID()
    public func setMicrophoneMuted(_ muted: Bool) {
        microphoneMuted = muted; microphoneEpoch = UUID()
        buffers[.microphone] = nil; assemblers[.microphone]?.discontinuity(); lastFrames[.microphone] = nil
        pending.removeAll { $0.metadata.source == .microphone }
        fullDecodeFallback = fullDecodeFallback.filter { $0.value.first?.metadata.source != .microphone }
    }
    private var decoding = false
    private var decodeTask: Task<Void, Never>?
    private var running = false
    private var epoch = UUID()
    private var lastFrames: [AudioSource: Date] = [:]
    private var lastLevelEvent: [AudioSource: Date] = [:]
    private var settings = CopilotSettings()
    private var contextVocabulary = ""
    public func setContextVocabulary(_ terms: String) { contextVocabulary = String(terms.prefix(900)) }
    private var handler: (@Sendable (PipelineEvent) async -> Void)?
    public init(speech: SpeechRecognitionService) {
        QueuedAudioChunk.cleanupStaleDirectories()
        transcribe = { samples, language, vocabulary in try await speech.transcribe(samples, language: language, vocabulary: vocabulary) }
    }
    public init(transcribe: @escaping @Sendable ([Float], String, String) async throws -> SpeechResult) { self.transcribe = transcribe }
    public func run(frames: AsyncStream<AudioFrame>, settings: CopilotSettings, handler: @escaping @Sendable (PipelineEvent) async -> Void) async {
        if let decodeTask { decodeTask.cancel(); await decodeTask.value }
        decoding = false; decodeTask = nil
        self.settings = settings; self.handler = handler; running = true
        microphoneMuted = false; microphoneEpoch = UUID()
        buffers = [:]; assemblers = [:]; detector = QuestionDetectionService(); pending = []; fullDecodeFallback = [:]; epoch = UUID()
        metrics = SpeechPipelineStatistics()
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
                metrics.receivedSamples += frame.samples.count
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
    public func discontinuity() async {
        // Resampled PCM already in the queue remains valid after a route change.
        // Close each old utterance before a new capture device starts emitting.
        for (source, buffer) in buffers {
            if let chunk = buffer.value.flush(source: source) { await enqueue(chunk) }
        }
        buffers = [:]; lastFrames = [:]
    }
    public func cancel() {
        running = false; pending = []; fullDecodeFallback = [:]; buffers = [:]; epoch = UUID()
        decodeTask?.cancel()
        try? FileManager.default.removeItem(at: spoolDirectory)
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
        try? FileManager.default.removeItem(at: spoolDirectory)
    }
    private func enqueue(_ chunk: AudioChunk) async {
        if chunk.replacesUtterance {
            // The complete utterance supersedes queued six-second windows.
            // Prioritize it so a long question does not wait behind every
            // redundant preview; preserve the windows if this decode is blank.
            let insertion = pending.firstIndex(where: { $0.metadata.utterance == chunk.utterance }) ?? pending.count
            let old = pending.filter { $0.metadata.utterance == chunk.utterance }
            pending.removeAll { $0.metadata.utterance == chunk.utterance }
            var fallback = old
            if let samples = chunk.fallbackSamples {
                fallback.append(QueuedAudioChunk(AudioChunk(samples: samples, source: chunk.source, final: true, utterance: chunk.utterance,
                                           window: chunk.window, overlapsPrevious: chunk.window > 0, capturedAt: chunk.capturedAt)))
            }
            fullDecodeFallback[chunk.utterance] = fallback
            pending.insert(QueuedAudioChunk(chunk), at: min(insertion, pending.count))
            await compactQueue()
            if !decoding { decoding = true; decodeTask = Task { await self.drain() } }
            return
        }
        // Coalesce interim snapshots of the same window; retain final results.
        pending.removeAll { $0.metadata.utterance == chunk.utterance && $0.metadata.window == chunk.window && $0.metadata.isPreview }
        if pending.count >= 4 {
            // A final window carries unique words from a long question. Only
            // provisional previews may be discarded under decoder pressure.
            if let preview = pending.firstIndex(where: { $0.metadata.isPreview }) {
                pending.remove(at: preview)
            } else if chunk.isPreview {
                return
            }
        }
        pending.append(QueuedAudioChunk(chunk))
        await compactQueue()
        if !decoding { decoding = true; decodeTask = Task { await self.drain() } }
    }
    private func compactQueue() async {
        let all = pending + fullDecodeFallback.values.flatMap { $0 }
        var resident = all.reduce(0) { $0 + $1.residentSampleCount }
        do {
            for item in all where resident > 90 * 16000 {
                let count = item.residentSampleCount
                try item.spill(to: spoolDirectory); resident -= count
                if count > 0 { metrics.spilledChunks += 1 }
            }
            metrics.peakResidentQueuedSamples = max(metrics.peakResidentQueuedSamples, resident)
            if all.reduce(0, { $0 + $1.spooledBytes }) > 512 * 1024 * 1024 {
                throw CopilotError.message("Speech backlog exceeded 512 MB; stop capture and let recognition finish")
            }
            let seconds = pending.reduce(0) { $0 + Double($1.sampleCount) / 16000 }
            metrics.peakQueueSeconds = max(metrics.peakQueueSeconds, seconds)
            if seconds > 15 && Date().timeIntervalSince(queueWarningAt) > 10 {
                queueWarningAt = Date()
                await handler?(PipelineEvent(source: .system, pendingSeconds: seconds))
            }
        } catch {
            await handler?(PipelineEvent(source: .system, error: "Audio backlog: " + error.localizedDescription, fatal: true))
        }
    }
    private func drain() async {
        defer { decoding = false; decodeTask = nil }
        while !pending.isEmpty && running {
            let item = pending.removeFirst(); let chunk = item.metadata; let currentEpoch = epoch; let micEpoch = microphoneEpoch
            do {
                let chunk = try item.load()
                let result = try await transcribe(chunk.samples, settings.language, settings.speechVocabulary + " " + contextVocabulary)
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
                if update.completedUtterance != nil { metrics.completedUtterances += 1 }
                var question: String?
                if let completed = update.completedUtterance, chunk.source == .system || settings.answerFromMicrophone {
                    question = detector.completed(completed)
                }
                await handler?(PipelineEvent(source: chunk.source, update: update, seconds: result.seconds, question: question,
                                             finalAudioSeconds: chunk.final ? Double(chunk.samples.count) / 16000 : nil,
                                             wholeUtteranceDecode: chunk.final ? chunk.replacesUtterance : nil,
                                             utterance: chunk.utterance, capturedAt: chunk.capturedAt,
                                             pendingSeconds: pending.reduce(0) { $0 + Double($1.sampleCount) / 16000 }))
            } catch {
                guard running, currentEpoch == epoch, chunk.source != .microphone || (!microphoneMuted && micEpoch == microphoneEpoch) else { continue }
                if chunk.replacesUtterance, let fallback = fullDecodeFallback.removeValue(forKey: chunk.utterance), !fallback.isEmpty {
                    pending.insert(contentsOf: fallback, at: 0)
                    continue
                }
                if !chunk.isPreview, item.attempts < 2, !Task.isCancelled {
                    item.attempts += 1; pending.insert(item, at: 0)
                    metrics.decoderRetries += 1
                    try? await Task.sleep(for: .milliseconds(200))
                    continue
                }
                if !chunk.isPreview {
                    await handler?(PipelineEvent(source: chunk.source, error: "Speech recognition failed after retries: " + error.localizedDescription,
                                                 utterance: chunk.utterance, capturedAt: chunk.capturedAt, recognitionGap: true))
                }
            }
        }
    }
}

private final class AudioBufferBox {
    var value = AudioBufferManager()
}
