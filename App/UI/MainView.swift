import SwiftUI
import LocalCopilotCore

extension AudioMode {
    var label: String { switch self { case .system: "Звук програм"; case .microphone: "Мікрофон"; case .both: "Обидва" } }
}
private func clock(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }

struct MainView: View {
    @ObservedObject var model: ConversationManager
    @State private var selection = "Live"
    @State private var showSource = false
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Розмова", systemImage: "waveform").tag("Live")
                Label("Контекст і код", systemImage: "chevron.left.forwardslash.chevron.right").tag("Context")
                Label("Історія", systemImage: "clock.arrow.circlepath").tag("History")
                Label("Діагностика", systemImage: "stethoscope").tag("Diagnostics")
            }.navigationTitle("Questionio").navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                Label { VStack(alignment: .leading, spacing: 2) { Text("Усе локально").font(.caption.weight(.medium)); Text("Whisper + Ollama · без хмари").font(.caption2).foregroundStyle(.secondary) } } icon: { Image(systemName: "lock.shield.fill").foregroundStyle(.green) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        } detail: {
            Group {
                if selection == "Context" { SessionContextView(model: model) }
                else if selection == "History" { HistoryView(model: model) }
                else if selection == "Diagnostics" { DiagnosticsView(model: model) }
                else { LiveView(model: model) }
            }.background(.background.secondary)
        }.frame(minWidth: 900, minHeight: 620).appColorScheme(model.settings.appearance)
        .toolbar {
            ToolbarItemGroup {
                Button { showSource.toggle() } label: { Label("Джерело звуку", systemImage: "slider.horizontal.3") }
                    .help("Джерело звуку").popover(isPresented: $showSource, arrowEdge: .bottom) { CaptureSourceView(model: model).frame(width: 440).padding(16) }
                Button { Task { await model.newConversation() } } label: { Label("Нова сесія", systemImage: "plus") }.help("Нова сесія").disabled(model.starting || model.stopping)
                Button { model.togglePanel?() } label: { Label("Плаваюче вікно", systemImage: "pip") }.help("Плаваюче вікно")
                Menu {
                    Button("Зберегти діалог…") { Task { await model.exportDialogue() } }.disabled(model.transcriptCount == 0)
                    Button("Відновити останній діалог") { Task { await model.recoverDialogue() } }.disabled(model.running || model.starting || model.stopping)
                } label: { Label("Ще", systemImage: "ellipsis.circle") }
                SettingsLink { Label("Налаштування", systemImage: "gearshape") }.help("Налаштування")
            }
        }
    }
}

struct RecordButton: View {
    @ObservedObject var model: ConversationManager
    var size: CGFloat = 48
    @State private var pulse = false
    var body: some View {
        Button { Task { if model.running { await model.stop() } else { await model.start() } } } label: {
            ZStack {
                if model.running { Circle().stroke(.red.opacity(0.35), lineWidth: 3).scaleEffect(pulse ? 1.25 : 1).opacity(pulse ? 0 : 1) }
                Circle().fill(model.running ? Color.red.gradient : Color.accentColor.gradient)
                if model.starting || model.stopping { ProgressView().controlSize(.small).tint(.white) }
                else { Image(systemName: model.running ? "stop.fill" : "mic.fill").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white) }
            }.frame(width: size, height: size).contentShape(Circle())
        }.buttonStyle(.plain).disabled(model.starting || model.stopping || model.modelBusy)
        .help(model.running ? "Зупинити запис (⌃⌥⌘R)" : "Почати запис (⌃⌥⌘R)")
        .onChange(of: model.running, initial: true) { _, running in
            pulse = false
            if running { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
        }
    }
}

struct LiveView: View {
    @ObservedObject var model: ConversationManager
    @State private var transcriptSource = AudioSource.system
    @State private var transcriptExpanded = true
    private var warnings: [String] {
        var result: [String] = []
        if model.pendingAudioSeconds > 3 { result.append("Черга розпізнавання: \(Int(model.pendingAudioSeconds)) с") }
        if model.recognitionGaps > 0 { result.append("Нерозпізнані фрагменти: \(model.recognitionGaps)") }
        if model.droppedAudioFrames > 0 { result.append("Втрачено кадрів: \(model.droppedAudioFrames)") }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.error.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(model.error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { model.error = "" } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }.foregroundStyle(.orange).padding(12).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HSplitView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader("Питання", symbol: "questionmark.bubble") {
                            Text("\(model.questionInbox.entries.count)").font(.caption.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 8).padding(.vertical, 2).background(.quaternary, in: Capsule())
                        }
                        QuestionInboxView(model: model)
                    }.card().frame(minHeight: 180)
                    transcript
                }.frame(minWidth: 300, idealWidth: 380)
                AnswerCard(model: model).frame(minWidth: 340)
            }
            composer
        }.padding(20)
    }
    private var header: some View {
        VStack(spacing: 12) {
            headerTop
            HStack(spacing: 20) {
                if model.settings.effectiveAudioMode != .microphone { AudioMeter(label: "Співрозмовник", level: model.systemLevel, status: model.systemStatus, symbol: "speaker.wave.2") }
                if model.settings.effectiveAudioMode != .system { AudioMeter(label: "Я", level: model.micLevel, status: model.micStatus, symbol: "mic") }
                CompactProjectContext(project: model.project).frame(maxWidth: 260, alignment: .trailing)
            }
        }.card(padding: 14)
    }
    private var headerTop: some View {
        HStack(alignment: .center, spacing: 16) {
            RecordButton(model: model)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.stopping ? "Завершую розпізнавання…" : model.starting ? "Запускаю…" : model.running ? "Слухаю · \(clock(model.sessionSeconds))" : "Готово до запису")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text(model.running ? model.captureSourceName : model.configuredSourceName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if !warnings.isEmpty {
                        Label("\(warnings.count)", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(.orange.opacity(0.12), in: Capsule())
                            .help(warnings.joined(separator: "\n"))
                    }
                    StatusPill(title: "Голос", value: model.whisperStatus, symbol: "waveform")
                    StatusPill(title: "AI", value: model.ollamaStatus, symbol: "cpu")
                }
                HStack(spacing: 14) {
                    Toggle("Автовідповіді", isOn: $model.settings.automatic)
                    Toggle("Швидкий режим · 4B", isOn: $model.settings.fastAnswers).help("Швидше, але може помилятися в коді")
                }.toggleStyle(.switch).controlSize(.mini).font(.caption)
            }
        }
    }
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Транскрипт", symbol: "text.quote") {
                if model.settings.effectiveAudioMode == .both {
                    Picker("", selection: $transcriptSource) { Text("Співрозмовник").tag(AudioSource.system); Text("Я").tag(AudioSource.microphone) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                Button { withAnimation(.snappy) { transcriptExpanded.toggle() } } label: { Image(systemName: transcriptExpanded ? "chevron.down" : "chevron.right") }
                    .buttonStyle(.borderless).help(transcriptExpanded ? "Згорнути" : "Розгорнути")
            }
            if transcriptExpanded {
                let source = model.settings.effectiveAudioMode == .microphone ? .microphone : (model.settings.effectiveAudioMode == .system ? .system : transcriptSource)
                TranscriptCard(confirmed: source == .system ? model.systemTranscript : model.microphoneTranscript,
                               interim: source == .system ? model.systemInterim : model.microphoneInterim)
                Text("Сірий текст — чернетка · останнє розпізнавання \(model.decodeSeconds, specifier: "%.2f") с · \(model.transcriptCount) записів")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
        }.card().frame(minHeight: transcriptExpanded ? 160 : nil)
    }
    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor").foregroundStyle(.tertiary)
            TextField("Поставте питання або натисніть Enter для останньої фрази…", text: $model.manualQuestion, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4).onSubmit { model.generateManual() }
            Button { model.generateManual() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 24)) }
                .buttonStyle(.plain).foregroundStyle(.tint).help("Відповісти (⌃⌥⌘G)").keyboardShortcut(.return, modifiers: .command)
        }.padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}

struct FloatingView: View {
    @ObservedObject var model: ConversationManager
    @State private var showSource = false
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                RecordButton(model: model, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.running ? "Слухаю · \(clock(model.sessionSeconds))" : "Questionio").font(.caption.weight(.semibold)).monospacedDigit()
                    Text((model.running ? model.captureSourceName : model.configuredSourceName) + (model.project.rootPath.isEmpty ? "" : " · " + URL(fileURLWithPath: model.project.rootPath).lastPathComponent))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.settings.effectiveAudioMode != .system {
                    Button { model.toggleMySpeaking() } label: { Image(systemName: model.mySpeaking ? "mic.slash.fill" : "mic") }
                        .buttonStyle(.borderless).disabled(!model.running).help(model.mySpeaking ? "Слухати далі" : "Я говорю · пауза мікрофона (⌃⌥⌘M)")
                }
                QuestionInboxView(model: model, compact: true).fixedSize()
                Button { showSource.toggle() } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).help("Джерело звуку")
                    .popover(isPresented: $showSource) { CaptureSourceView(model: model).frame(width: 420).padding(16) }
                Toggle(isOn: $model.settings.alwaysOnTop) { Image(systemName: "pin") }.toggleStyle(.button).buttonStyle(.borderless)
                    .disabled(model.settings.privateWindow).help("Поверх інших вікон")
            }
            AnswerCard(model: model, compact: true)
            HStack(spacing: 8) {
                TextField("Питання…", text: $model.manualQuestion).textFieldStyle(.plain).onSubmit { model.generateManual() }
                Button { model.generateManual() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }.buttonStyle(.plain).foregroundStyle(.tint)
            }.padding(.horizontal, 12).padding(.vertical, 8).background(.quaternary.opacity(0.5), in: Capsule())
            if !model.error.isEmpty { Label(model.error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(3).help(model.error) }
        }.padding(12).frame(minWidth: 340, minHeight: 260).background(.ultraThinMaterial).appColorScheme(model.settings.appearance)
    }
}

struct HistoryView: View {
    @ObservedObject var model: ConversationManager
    @State private var confirmDelete = false
    @State private var search = ""
    private var records: [ConversationRecord] {
        search.isEmpty ? model.history : model.history.filter { $0.question.localizedCaseInsensitiveContains(search) || $0.answer.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Історія").font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Видалити все", role: .destructive) { confirmDelete = true }.disabled(model.history.isEmpty)
            }
            TextField("Пошук у питаннях і відповідях", text: $search).textFieldStyle(.roundedBorder)
            if records.isEmpty {
                EmptyState(symbol: "clock", title: model.history.isEmpty ? "Історія порожня" : "Нічого не знайдено", hint: "Завершені відповіді зберігаються тут, якщо збереження історії увімкнено.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Продовжити") { model.restore(record) }.controlSize(.small) }
                                Text(record.question).font(.headline).textSelection(.enabled)
                                Text(record.answer).foregroundStyle(.secondary).lineLimit(6).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 14)
                        }
                    }
                }
            }
        }.padding(20)
        .alert("Видалити всю локальну історію?", isPresented: $confirmDelete) { Button("Видалити", role: .destructive) { Task { await model.clearHistory() } }; Button("Скасувати", role: .cancel) {} } message: { Text("Збережені питання, відповіді та журнали діалогів буде остаточно видалено з цього Mac.") }
    }
}

struct CaptureSourceView: View {
    @ObservedObject var model: ConversationManager
    private var locked: Bool { model.running || model.starting || model.stopping }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Джерело звуку").font(.headline)
            Picker("Сценарій", selection: Binding(get: { model.settings.listeningProfile }, set: { model.selectListeningProfile($0) })) { ForEach(ListeningProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().disabled(locked)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Захоплення").foregroundStyle(.secondary)
                    Picker("", selection: $model.settings.audioMode) { ForEach(AudioMode.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden()
                }
                GridRow {
                    Text("Програма").foregroundStyle(.secondary)
                    HStack {
                        Picker("", selection: $model.settings.applicationID) {
                            Text("Усі програми").tag("")
                            ForEach(model.applications) { Text($0.name).tag($0.bundleID) }
                            if !model.settings.applicationID.isEmpty && !model.applications.contains(where: { $0.id == model.settings.applicationID }) { Text(model.settings.applicationID).tag(model.settings.applicationID) }
                        }.labelsHidden().disabled(model.settings.audioMode == .microphone)
                        Button { Task { await model.refreshApplications() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Оновити програми")
                    }
                }
                if model.settings.effectiveAudioMode != .system {
                    GridRow {
                        Text("Мікрофон").foregroundStyle(.secondary)
                        Picker("", selection: $model.settings.microphoneID) { Text("Системний").tag(UInt32(0)); ForEach(model.microphones) { Text($0.name).tag($0.id) } }.labelsHidden()
                    }
                }
                GridRow {
                    Text("Терміни").foregroundStyle(.secondary)
                    Picker("", selection: $model.settings.vocabularyProfile) { ForEach(SpeechVocabulary.profiles, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                }
            }.disabled(locked || model.diagnostics.testing)
            Toggle("Записувати й мій мікрофон у режимі «Обидва»", isOn: $model.settings.captureMyVoice).disabled(locked)
            if model.settings.effectiveAudioMode != .system {
                Button(model.mySpeaking ? "Слухати далі" : "Я говорю · пауза мікрофона") { model.toggleMySpeaking() }.disabled(!model.running).help("⌃⌥⌘M · у спільному мікрофоні голоси розділяються вручну")
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label(model.running ? model.captureSourceName : model.configuredSourceName, systemImage: "app.badge")
                Label(model.microphoneDeviceName + " · " + model.micStatus, systemImage: "mic")
                Label("Вихід: " + model.outputDeviceName, systemImage: "headphones")
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Власні терміни — у Налаштуваннях → Розпізнавання").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button { model.settings.privateWindow.toggle() } label: { Label(model.settings.privateWindow ? "Ghost ON" : "Ghost OFF", systemImage: model.settings.privateWindow ? "eye.slash" : "eye") }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}

struct CompactProjectContext: View {
    @ObservedObject var project: ProjectContextService
    var body: some View {
        Button { project.chooseFolder() } label: {
            Label(project.rootPath.isEmpty ? "Підключити папку з кодом" : URL(fileURLWithPath: project.rootPath).lastPathComponent + " · \(project.files.count) файлів", systemImage: project.rootPath.isEmpty ? "folder.badge.plus" : "folder.fill")
                .font(.caption).lineLimit(1)
        }.buttonStyle(.bordered).controlSize(.small).help(project.rootPath.isEmpty ? "Вибрати папку проєкту" : project.rootPath + " · натисніть, щоб змінити")
    }
}

struct QuestionInboxView: View {
    @ObservedObject var model: ConversationManager
    var compact = false
    @State private var search = ""
    private var visible: [QuestionInbox.Entry] { model.questionInbox.entries.reversed().filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) } }
    private func tint(_ state: DialogueQuestionState) -> Color { state == .ready ? .accentColor : state == .draft ? .orange : .gray }
    var body: some View {
        if compact {
            Menu { ForEach(model.questionInbox.entries.reversed()) { item in Button("[\(item.state.rawValue)] " + item.text) { model.answerSelectedQuestion(item) } } }
                label: { Label("\(model.questionInbox.entries.count)", systemImage: "questionmark.bubble") }
                .menuStyle(.borderlessButton).disabled(model.questionInbox.entries.isEmpty).help("Питання діалогу")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if model.questionInbox.entries.isEmpty {
                    EmptyState(symbol: "questionmark.bubble", title: "Питань поки немає", hint: "Після старту тут з’являться розпізнані питання. Натисніть на питання, щоб отримати відповідь.")
                } else {
                    if model.questionInbox.entries.count > 5 { TextField("Знайти питання…", text: $search).textFieldStyle(.roundedBorder).controlSize(.small) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(visible) { item in
                                Button { model.answerSelectedQuestion(item) } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        RoundedRectangle(cornerRadius: 2).fill(tint(item.state)).frame(width: 3)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.text).lineLimit(3).multilineTextAlignment(.leading)
                                            Text(item.state.rawValue + " · " + item.source + " · " + item.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(tint(item.state).opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text(model.recognizedQuestionNote.isEmpty ? model.autoAnswerStatus + " · " + model.dialogueStatus : model.recognizedQuestionNote)
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
