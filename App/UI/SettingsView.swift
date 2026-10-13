import SwiftUI
import AppKit
import LocalCopilotCore
struct SettingsView: View {
    @ObservedObject var model: ConversationManager
    @ObservedObject var diagnostics: DiagnosticsManager
    init(model: ConversationManager) { self.model = model; self.diagnostics = model.diagnostics }
    @State private var section = "General"
    private let sections = ["General", "Audio", "Speech Recognition", "AI Models", "Answer Behavior", "Appearance", "Hotkeys", "Privacy", "Diagnostics"]
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $section) { Text($0).tag($0) }.navigationSplitViewColumnWidth(180)
        } detail: {
            if section == "Diagnostics" { DiagnosticsView(model: model) }
            else {
                Form {
                    switch section {
                    case "General":
                        Section("Questionio") { Toggle("Automatically answer completed questions", isOn: $model.settings.automatic); Toggle("Save question / answer history locally", isOn: $model.settings.saveHistory); Text("Start capture explicitly. Audio remains in memory and is never saved.").foregroundStyle(.secondary) }
                    case "Audio":
                        Section("Sources") {
                            Picker("System audio engine", selection: $model.settings.audioBackend) { Text("Core Audio Tap · audio only").tag("Core Audio Tap"); Text("ScreenCaptureKit").tag("ScreenCaptureKit") }
                            Picker("Capture mode", selection: $model.settings.audioMode) { ForEach(AudioMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            Picker("Microphone", selection: $model.settings.microphoneID) { Text("System default").tag(UInt32(0)); ForEach(model.microphones) { Text($0.name).tag($0.id) } }
                            Picker("System audio source", selection: $model.settings.applicationID) { Text("All applications (excluding Questionio)").tag(""); ForEach(model.applications) { Text($0.name).tag($0.bundleID) }; if !model.settings.applicationID.isEmpty && !model.applications.contains(where: { $0.bundleID == model.settings.applicationID }) { Text(model.settings.applicationID).tag(model.settings.applicationID) } }
                            Button("Refresh running applications") { Task { await model.refreshApplications() } }
                            Toggle("Capture my microphone in Both", isOn: $model.settings.captureMyVoice)
                            Toggle("Allow automatic answers from microphone", isOn: $model.settings.answerFromMicrophone)
                            Text("Stop and restart capture after source changes. AirPods appear when macOS exposes them as an input device.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(model.running || model.starting || diagnostics.testing)
                        Section("Signal") { AudioMeter(label: "Microphone", level: model.micLevel, status: model.micStatus); AudioMeter(label: "System", level: model.systemLevel, status: model.systemStatus) }
                    case "Speech Recognition":
                        Section("Offline Whisper") {
                            Text("Installed Whisper loads automatically when Questionio opens.").font(.caption).foregroundStyle(.secondary)
                            Picker("Download model", selection: $model.settings.whisperVariant) { Text("Whisper Large v3 Turbo · multilingual (accuracy)").tag("openai_whisper-large-v3-v20240930_turbo"); Text("Whisper small · multilingual (lighter)").tag("openai_whisper-small"); Text("Whisper base · multilingual (faster)").tag("openai_whisper-base") }
                            TextField("Local model directory", text: $model.settings.modelPath)
                            HStack { Button("Download once & load") { Task { await model.downloadModel() } }; Button("Load local model") { Task { await model.loadModel() } }; Button("Choose folder…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK, let url = panel.url { model.settings.modelPath = url.path } } }
                            Text(model.whisperStatus).foregroundStyle(.secondary)
                            Text("Download explicitly contacts Hugging Face. Subsequent loading and recognition use local files only. Keep the multilingual model for Ukrainian; small uses several hundred MB; Large v3 Turbo uses more memory and about 1.6 GB on disk.").font(.caption).foregroundStyle(.secondary)
                            Picker("Vocabulary profile", selection: $model.settings.vocabularyProfile) { ForEach(SpeechVocabulary.profiles, id: \.self) { Text($0).tag($0) } }
                            TextField("Custom vocabulary: APIs, names, project terms", text: $model.settings.customVocabulary, axis: .vertical).lineLimit(2...4)
                            Picker("Language", selection: $model.settings.language) { Text("Automatic").tag("auto"); Text("Українська").tag("uk"); Text("English").tag("en"); Text("Polski").tag("pl"); Text("Deutsch").tag("de"); Text("Français").tag("fr"); Text("Español").tag("es") }
                            LabeledContent("Pause before confirming") { Slider(value: $model.settings.silenceSeconds, in: 0.5...2, step: 0.05); Text(String(format: "%.2f s", model.settings.silenceSeconds)).monospacedDigit() }
                            LabeledContent("Max chunk") { Slider(value: $model.settings.chunkSeconds, in: 4...12, step: 1); Text("\(Int(model.settings.chunkSeconds)) s") }
                            LabeledContent("VAD RMS threshold") { Slider(value: $model.settings.vadThreshold, in: 0.002...0.04); Text(String(format: "%.3f", model.settings.vadThreshold)) }
                            Text("Energy VAD, 0.5 s overlap, at most one interim decode per window. Actual latency depends on utterance length and decode time; change these values while stopped.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(model.running || model.starting || model.modelBusy || diagnostics.testing)
                    case "AI Models":
                        Section("Ollama · 127.0.0.1:11434") {
                            Picker("Installed model", selection: $model.settings.model) { ForEach(model.models) { Text($0.name + " · " + String(format: "%.1f GB", Double($0.size) / 1e9)).tag($0.name) }; if !model.models.contains(where: { $0.name == model.settings.model }) { Text(model.settings.model).tag(model.settings.model) } }
                            Button("Refresh models") { Task { await model.refreshModels() } }
                            Toggle("Thinking mode (supported models only)", isOn: $model.settings.thinking)
                            Text("Qwen2.5-Coder:7b is a coding option for this 16 GB Mac (~4.7 GB weights). Qwen3.5:4b is faster. One generation at a time; all inference is local.").foregroundStyle(.secondary)
                            Picker("Context window", selection: $model.settings.contextTokens) { Text("2048 tokens").tag(2048); Text("4096 tokens").tag(4096); Text("8192 tokens").tag(8192); Text("16384 tokens · more memory").tag(16384) }
                            Stepper("Context text budget: \(model.settings.contextCharacters) characters", value: $model.settings.contextCharacters, in: 2000...12000, step: 1000)
                        }
                    case "Answer Behavior":
                        Section("Style") { Toggle("Automatic answers", isOn: $model.settings.automatic); Slider(value: $model.settings.temperature, in: 0...1); Text("Temperature: \(model.settings.temperature, specifier: "%.2f")"); Toggle("Complete answers · no output token cap", isOn: Binding(get: { model.settings.maxTokens <= 0 }, set: { model.settings.maxTokens = $0 ? -1 : 2048 })); if model.settings.maxTokens > 0 { Stepper("Maximum answer tokens: \(model.settings.maxTokens)", value: $model.settings.maxTokens, in: 256...32768, step: 256) }; Text("Without an output cap, generation continues until the model finishes or you press Cancel. Context capacity and memory remain finite.").font(.caption).foregroundStyle(.secondary); Button("Use developer conversation style") { model.settings.systemPrompt = CopilotSettings.developerPrompt }; Text("System prompt"); TextEditor(text: $model.settings.systemPrompt).font(.body).frame(height: 170).border(.quaternary); Text("Automatic question detection supports Ukrainian and English question patterns. Other Whisper languages remain available for manual answers.").font(.caption).foregroundStyle(.secondary) }
                    case "Appearance":
                        Section("Windows") { Picker("Theme", selection: $model.settings.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }; Toggle("Floating window always on top", isOn: $model.settings.alwaysOnTop).disabled(model.settings.privateWindow); Text("Ghost mode keeps Notes above full-screen applications. In normal mode, Top applies only to regular desktop windows.").font(.caption).foregroundStyle(.secondary); Button("Show / hide floating window") { model.togglePanel?() } }
                    case "Hotkeys":
                        Section("Global shortcuts") { Toggle("Enable global shortcuts", isOn: $model.settings.hotkeysEnabled); LabeledContent("Generate Answer", value: "⌃ ⌥ ⌘ G"); LabeledContent("Start / Stop audio", value: "⌃ ⌥ ⌘ R"); LabeledContent("Show / hide floating window", value: "⌃ ⌥ ⌘ P"); Text("Shortcuts use the macOS Carbon hotkey API and do not require Accessibility permission. Conflicts are reported in Diagnostics.").font(.caption).foregroundStyle(.secondary) }
                    case "Privacy":
                        Section("Data") { Toggle("Save local question / answer history", isOn: $model.settings.saveHistory); Toggle("Request capture exclusion · experimental", isOn: $model.settings.privateWindow); Text("AppKit capture exclusion is requested, but full-display sharing may still show this window on modern macOS. This is not a guaranteed ghost mode. For reliable separation, share one application window or another display. Audio is never written to disk; no analytics or telemetry.").foregroundStyle(.secondary); Text("History: ~/Library/Application Support/LocalCopilot/history.sqlite").font(.caption).textSelection(.enabled) }
                        Button("Test full-display capture exclusion") { Task { await model.testWindowPrivacy() } }.disabled(diagnostics.testing)
                        Section("Permissions") { LabeledContent("Microphone", value: PermissionsManager.microphoneStatus); LabeledContent("Screen / system audio", value: PermissionsManager.screenStatus); Button("Microphone settings") { PermissionsManager.openPrivacy("Privacy_Microphone") }; Button("Screen & System Audio Recording settings") { PermissionsManager.openPrivacy("Privacy_ScreenCapture") } }
                    default: EmptyView()
                    }
                }.formStyle(.grouped).navigationTitle(section)
            }
        }.frame(width: 840, height: 630).preferredColorScheme(model.settings.appearance == "dark" ? .dark : model.settings.appearance == "light" ? .light : nil)
    }
}
struct DiagnosticsView: View {
    @ObservedObject var model: ConversationManager
    @ObservedObject var diagnostics: DiagnosticsManager
    init(model: ConversationManager) { self.model = model; diagnostics = model.diagnostics }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics").font(.title2.bold())
            Text("Audio tests listen for 5 seconds. Speak for microphone, or play sound in your selected application. Tests do not store audio.").foregroundStyle(.secondary)
            HStack { Button("Test microphone") { Task { await model.testAudio(.microphone) } }; Button("Test system audio") { Task { await model.testAudio(.system) } }; Button("Test Whisper · audio file") { Task { await model.testWhisperFile() } }; Button("Test Ollama") { Task { await diagnostics.testOllama(model.ollama, settings: model.settings) } } }.disabled(diagnostics.testing || model.running || model.starting || model.modelBusy || model.generating)
            if diagnostics.testing { ProgressView() }
            AudioMeter(label: "Microphone", level: model.micLevel, status: model.micStatus)
            AudioMeter(label: "System audio", level: model.systemLevel, status: model.systemStatus)
            ScrollView { Text(diagnostics.lines.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            Text("Log stays in memory. API timeout: 45 s inactivity; no short total generation deadline. No network calls except localhost and explicit model downloads.").font(.caption).foregroundStyle(.secondary)
        }.padding(22)
    }
}
