import SwiftUI
import LocalCopilotCore
struct MainView: View {
    @ObservedObject var model: ConversationManager
    @State private var selection = "Live"
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Live session", systemImage: "waveform").tag("Live")
                Label("Context / Code", systemImage: "text.viewfinder").tag("Context")
                Label("History", systemImage: "clock.arrow.circlepath").tag("History")
                Label("Diagnostics", systemImage: "stethoscope").tag("Diagnostics")
            }.navigationTitle("Questionio").navigationSplitViewColumnWidth(min: 150, ideal: 170)
            VStack(alignment: .leading, spacing: 6) { Label("Local processing", systemImage: "lock.shield"); Text("Whisper + Ollama\nТимчасовий аудіокеш при затримці").font(.caption).foregroundStyle(.secondary) }.padding()
        } detail: {
            if selection == "Context" { SessionContextView(model: model) }
            else if selection == "History" { HistoryView(model: model) }
            else if selection == "Diagnostics" { DiagnosticsView(model: model) }
            else { live }
        }.frame(minWidth: 880, minHeight: 600).preferredColorScheme(model.settings.appearance == "dark" ? .dark : model.settings.appearance == "light" ? .light : nil)
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.newConversation() } } label: { Label("New session", systemImage: "plus") }.disabled(model.starting || model.stopping)
                Button { model.togglePanel?() } label: { Label("Floating window", systemImage: "pip") }
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }
        }
    }
    private var live: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Your local conversation copilot").font(.title2.weight(.semibold)); Text("Listen, understand, and answer — on this Mac.").foregroundStyle(.secondary) }
                Spacer()
                Button { Task { if model.running { await model.stop() } else { await model.start() } } } label: { Label(model.stopping ? "Finishing…" : model.starting ? "Starting…" : model.running ? "Stop" : "Start", systemImage: model.running ? "stop.fill" : "play.fill") }.buttonStyle(.borderedProminent).disabled(model.starting || model.stopping || model.modelBusy)
            }
            HStack { StatusPill(title: "Whisper", value: model.whisperStatus); StatusPill(title: "Ollama", value: model.ollamaStatus); Spacer(); Toggle("Automatic answers", isOn: $model.settings.automatic).toggleStyle(.switch).controlSize(.small) }
            HStack {
                Text("Діалог \(Int(model.sessionSeconds) / 60):\(String(format: "%02d", Int(model.sessionSeconds) % 60)) · \(model.transcriptCount) записів").monospacedDigit()
                if model.pendingAudioSeconds > 3 { Text("Черга розпізнавання: \(Int(model.pendingAudioSeconds)) с").foregroundStyle(.orange) }
                if model.recognitionGaps > 0 { Text("Нерозпізнані фрагменти: \(model.recognitionGaps)").foregroundStyle(.red) }
                if model.droppedAudioFrames > 0 { Text("Втрачено кадрів: \(model.droppedAudioFrames)").foregroundStyle(.red) }
                Spacer()
                Button("Зберегти діалог…") { Task { await model.exportDialogue() } }.disabled(model.transcriptCount == 0)
                Button("Відновити останній") { Task { await model.recoverDialogue() } }.disabled(model.running || model.starting || model.stopping)
            }.font(.caption)
            Toggle("Швидкий режим · 4B (може помилятися в коді)", isOn: $model.settings.fastAnswers).font(.caption)
            CompactProjectContext(project: model.project)
            if !model.editor.enabled || model.project.rootPath.isEmpty { CompactCodeContext(screen: model.screen) }
            CaptureSourceView(model: model)
            HStack(spacing: 24) { AudioMeter(label: "System audio", level: model.systemLevel, status: model.systemStatus); AudioMeter(label: "Microphone", level: model.micLevel, status: model.micStatus) }
            if !model.error.isEmpty { HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle"); Text(model.error).font(.caption).textSelection(.enabled); Spacer(); Button { model.error = "" } label: { Image(systemName: "xmark") } }.foregroundStyle(.orange).padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }
            HSplitView {
                VStack(spacing: 12) {
                    QuestionInboxView(model: model)
                    TranscriptCard(title: "Live Transcript · System", confirmed: model.systemTranscript, interim: model.systemInterim)
                    if model.settings.audioMode != .system { TranscriptCard(title: "Live Transcript · Microphone", confirmed: model.microphoneTranscript, interim: model.microphoneInterim) }
                    Text("Last decode: \(model.decodeSeconds, specifier: "%.2f") s · provisional text is gray").font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 260)
                AnswerCard(model: model).frame(minWidth: 280)
            }
            HStack {
                TextField("Ask a question, or use the latest completed utterance…", text: $model.manualQuestion, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder).onSubmit { model.generateManual() }
                Button("Generate Answer") { model.generateManual() }.buttonStyle(.borderedProminent)
            }
        }.padding(22)
    }
}
struct FloatingView: View {
    @ObservedObject var model: ConversationManager
    var body: some View {
        VStack(spacing: 8) {
            HStack { Label("Questionio", systemImage: "waveform").font(.caption.weight(.semibold)); Spacer(); Toggle("Top", isOn: $model.settings.alwaysOnTop).toggleStyle(.checkbox).disabled(model.settings.privateWindow).help("Ghost mode keeps Notes above full-screen apps automatically"); Button { Task { if model.running { await model.stop() } else { await model.start() } } } label: { Image(systemName: model.stopping ? "hourglass" : model.running ? "stop.fill" : "play.fill") }.disabled(model.starting || model.stopping || model.modelBusy) }
            CaptureSourceView(model: model, compact: true)
            CompactProjectContext(project: model.project)
            if !model.editor.enabled || model.project.rootPath.isEmpty { CompactCodeContext(screen: model.screen) }
            QuestionInboxView(model: model, compact: true)
            AnswerCard(model: model, compact: true)
            HStack { TextField("Question…", text: $model.manualQuestion).onSubmit { model.generateManual() }; Button("Answer") { model.generateManual() } }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.orange).lineLimit(3).help(model.error) }
        }.padding(10).frame(minWidth: 320, minHeight: 240).preferredColorScheme(model.settings.appearance == "dark" ? .dark : model.settings.appearance == "light" ? .light : nil)
    }
}
struct HistoryView: View {
    @ObservedObject var model: ConversationManager
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("Conversation history").font(.title2.bold()); Spacer(); Button("Delete all", role: .destructive) { confirmDelete = true } }.padding()
            List(model.history) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Continue") { model.restore(record) } }
                    Text(record.question).font(.headline).textSelection(.enabled)
                    Text(record.answer).textSelection(.enabled)
                }.padding(.vertical, 8)
            }
        }.alert("Delete all local history?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { Task { await model.clearHistory() } }; Button("Cancel", role: .cancel) {} } message: { Text("This permanently removes saved questions, answers, and full dialogue journals from this Mac.") }
    }
}

struct CaptureSourceView: View {
    @ObservedObject var model: ConversationManager
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !compact {
                Picker("Режим пари", selection: Binding(get: { model.settings.listeningProfile }, set: { model.selectListeningProfile($0) })) { ForEach(ListeningProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(model.running || model.starting || model.stopping)
                HStack {
                    Picker("Захоплення", selection: $model.settings.audioMode) { ForEach(AudioMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 220)
                    Picker("Програма", selection: $model.settings.applicationID) {
                        Text("Усі програми").tag("")
                        ForEach(model.applications) { Text($0.name).tag($0.bundleID) }
                        if !model.settings.applicationID.isEmpty && !model.applications.contains(where: { $0.id == model.settings.applicationID }) { Text(model.settings.applicationID).tag(model.settings.applicationID) }
                    }.disabled(model.settings.audioMode == .microphone)
                    Button { Task { await model.refreshApplications() } } label: { Image(systemName: "arrow.clockwise") }.help("Оновити програми")
                }.disabled(model.running || model.starting || model.stopping || model.diagnostics.testing)
                if model.settings.effectiveAudioMode != .system {
                    Picker("Мікрофон", selection: $model.settings.microphoneID) { Text("Системний за замовчуванням").tag(UInt32(0)); ForEach(model.microphones) { Text($0.name).tag($0.id) } }.disabled(model.running || model.starting)
                }
                Toggle("Захоплювати мій мікрофон у Both (типово слухає лише співрозмовника)", isOn: $model.settings.captureMyVoice).disabled(model.running || model.starting)
                HStack {
                    Picker("Терміни", selection: $model.settings.vocabularyProfile) { ForEach(SpeechVocabulary.profiles, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 250)
                    Text("Власні терміни — Settings → Speech Recognition").foregroundStyle(.secondary)
                }.disabled(model.running || model.starting)
            }
            if model.settings.effectiveAudioMode != .system {
                Button(model.mySpeaking ? "Слухати далі" : "Я говорю · пауза мікрофона") { model.toggleMySpeaking() }.disabled(!model.running).help("⌃⌥⌘M · у спільному мікрофоні голоси розділяються вручну")
            }
            Label("Джерело: " + (model.running ? model.captureSourceName : model.configuredSourceName), systemImage: "app.badge").lineLimit(compact ? 2 : 1)
            Label("Мікрофон: " + model.microphoneDeviceName + " · " + model.micStatus, systemImage: "mic")
            Label("Вихід macOS: " + model.outputDeviceName, systemImage: "headphones")
            HStack {
                Text(model.running ? "● Захоплення активне" : "Захоплення зупинено").foregroundStyle(model.running ? .green : .secondary)
                Spacer()
                Button { model.settings.privateWindow.toggle() } label: { Label(model.settings.privateWindow ? "Ghost ON" : "Ghost OFF", systemImage: model.settings.privateWindow ? "eye.slash" : "eye") }.buttonStyle(.bordered).controlSize(.small).help("Увімкнути / вимкнути ghost mode")
            }
            if !model.recognizedQuestionNote.isEmpty { Text(model.recognizedQuestionNote).foregroundStyle(.secondary).lineLimit(2) }
            Text(model.autoAnswerStatus).foregroundStyle(.secondary).lineLimit(compact ? 2 : 1)
            if compact && model.running { HStack { AudioMeter(label: "System", level: model.systemLevel, status: model.systemStatus); AudioMeter(label: "Mic", level: model.micLevel, status: model.micStatus) } }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CompactProjectContext: View {
    @ObservedObject var project: ProjectContextService
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(project.rootPath.isEmpty ? "Код лабораторної не підключено" : "Папка: " + URL(fileURLWithPath: project.rootPath).lastPathComponent + " · " + String(project.files.count) + " файлів", systemImage: "folder.badge.gearshape").font(.caption).lineLimit(2)
                if let profile = project.defenseProfile { Label(profile.name, systemImage: "function").font(.caption2).foregroundStyle(.blue) }
            }
            Spacer()
            Button(project.rootPath.isEmpty ? "Вибрати папку…" : "Змінити…") { project.chooseFolder() }.controlSize(.small)
        }
    }
}

struct QuestionInboxView: View {
    @ObservedObject var model: ConversationManager
    var compact = false
    @State private var search = ""
    private var visible: [QuestionInbox.Entry] { model.questionInbox.entries.reversed().filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        if compact {
            Menu("Питання діалогу · \(model.questionInbox.entries.count)") {
                ForEach(model.questionInbox.entries.reversed()) { item in
                    Button("[\(item.state.rawValue)] " + item.text) { model.answerSelectedQuestion(item) }
                }
            }.disabled(model.questionInbox.entries.isEmpty)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("Питання діалогу · натисніть для відповіді").font(.caption.bold())
                Text(model.dialogueStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                if model.questionInbox.entries.isEmpty {
                    Text("Після Start тут з’являться розпізнані питання. Для відповіді лише за кліком вимкніть Automatic answers.").font(.caption).foregroundStyle(.secondary)
                } else {
                    if model.questionInbox.entries.count > 5 { TextField("Знайти питання…", text: $search).textFieldStyle(.roundedBorder) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(visible) { item in
                                Button { model.answerSelectedQuestion(item) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.text).lineLimit(3).multilineTextAlignment(.leading)
                                        Text(item.state.rawValue + " · " + item.source + " · " + item.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.bordered).tint(item.state == .ready ? .blue : item.state == .draft ? .orange : .gray)
                            }
                        }
                    }.frame(maxHeight: 130)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
