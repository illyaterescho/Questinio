import SwiftUI
import LocalCopilotCore

extension AudioMode {
    var label: String { switch self { case .system: "Звук програм"; case .microphone: "Мікрофон"; case .both: "Обидва" } }
}
private func clock(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }

struct MainView: View {
    @ObservedObject var model: ConversationManager
    @State private var selection = "Live"
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Розмова", systemImage: "waveform").tag("Live")
                Label("Контекст і код", systemImage: "chevron.left.forwardslash.chevron.right").tag("Context")
                Label("Історія", systemImage: "clock.arrow.circlepath").tag("History")
                Label("Діагностика", systemImage: "stethoscope").tag("Diagnostics")
            }.navigationTitle("Questionio").navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                Label { VStack(alignment: .leading, spacing: 2) { Text("Усе локально").font(.caption.weight(.medium)); Text("без хмари й підписок").font(.caption2).foregroundStyle(.secondary) } } icon: { Image(systemName: "lock.shield.fill").foregroundStyle(.green) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        } detail: {
            Group {
                if selection == "Context" { SessionContextView(model: model) }
                else if selection == "History" { HistoryView(model: model) }
                else if selection == "Diagnostics" { DiagnosticsView(model: model) }
                else { LiveView(model: model) }
            }.background(AmbientBackground())
        }.frame(minWidth: 980, minHeight: 640).appColorScheme(model.settings.appearance)
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.newConversation() } } label: { Label("Нова сесія", systemImage: "square.and.pencil") }.help("Нова сесія").disabled(model.starting || model.stopping)
                Button { model.togglePanel?() } label: { Label("Плаваюче вікно", systemImage: "pip") }.help("Плаваюче вікно (⌃⌥⌘P)")
                Menu {
                    Button("Зберегти діалог…") { Task { await model.exportDialogue() } }.disabled(model.transcriptCount == 0)
                    Button("Відновити останній діалог") { Task { await model.recoverDialogue() } }.disabled(model.running || model.starting || model.stopping)
                } label: { Label("Ще", systemImage: "ellipsis") }
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
                if model.running { Circle().stroke(.red.opacity(0.35), lineWidth: 3).scaleEffect(pulse ? 1.3 : 1).opacity(pulse ? 0 : 1) }
                Group {
                    if model.starting || model.stopping { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: model.running ? "stop.fill" : "mic.fill").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white) }
                }.frame(width: size, height: size)
                .glass(Circle(), tint: model.running ? .red : .accentColor, interactive: true)
            }.frame(width: size, height: size).contentShape(Circle())
        }.buttonStyle(.plain).disabled(model.starting || model.stopping || model.modelBusy)
        .help(model.running ? "Зупинити запис (⌃⌥⌘R)" : "Почати запис (⌃⌥⌘R)")
        .onChange(of: model.running, initial: true) { _, running in
            pulse = false
            if running { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
        }
    }
}

/// Floating glass control that opens its own panel — the macOS Tahoe pattern.
struct GlassChip<Panel: View>: View {
    let symbol: String
    let title: String
    let value: String
    var tone: StatusTone?
    var accessory: AnyView?
    @ViewBuilder var panel: Panel
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        if let tone { Circle().fill(tone.color).frame(width: 6, height: 6) }
                        Text(value).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
                if let accessory { accessory }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).padding(.vertical, 7).contentShape(Capsule())
            .glass(Capsule(), interactive: true)
        }.buttonStyle(.plain).help(title + ": " + value)
        .popover(isPresented: $open, arrowEdge: .bottom) { panel.padding(16) }
    }
}
struct MiniMeter: View {
    let level: Float
    var body: some View {
        let fill = min(1, Double(level) * 8)
        ZStack(alignment: .bottom) {
            Capsule().fill(.primary.opacity(0.1))
            Capsule().fill(fill > 0.8 ? Color.orange : Color.green).frame(height: max(3, 18 * fill)).animation(.easeOut(duration: 0.12), value: fill)
        }.frame(width: 4, height: 18)
    }
}

struct LiveView: View {
    @ObservedObject var model: ConversationManager
    @State private var transcriptSource = AudioSource.system
    @State private var showTranscript = true
    private var warnings: [String] {
        var result: [String] = []
        if model.pendingAudioSeconds > 3 { result.append("Черга розпізнавання: \(Int(model.pendingAudioSeconds)) с") }
        if model.recognitionGaps > 0 { result.append("Нерозпізнані фрагменти: \(model.recognitionGaps)") }
        if model.droppedAudioFrames > 0 { result.append("Втрачено кадрів: \(model.droppedAudioFrames)") }
        return result
    }
    private var engineName: String { model.settings.speechEngine == "parakeet" ? "Parakeet v3" : "Whisper" }
    private var activeModel: String { model.settings.fastAnswers && model.models.contains(where: { $0.name == model.settings.fastModel }) ? model.settings.fastModel : model.settings.model }
    var body: some View {
        VStack(spacing: 16) {
            controlBar
            if !model.error.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(model.error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { model.error = "" } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }.foregroundStyle(.orange).padding(14).glass(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: .orange.opacity(0.25))
            }
            HSplitView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader("Питання", symbol: "questionmark.bubble") {
                            Text("\(model.questionInbox.entries.count)").font(.caption.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 9).padding(.vertical, 3).background(.primary.opacity(0.07), in: Capsule())
                        }
                        QuestionInboxView(model: model)
                    }.card().frame(minHeight: 200, maxHeight: .infinity)
                    transcript
                }.frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
                AnswerCard(model: model).frame(minWidth: 420, maxHeight: .infinity)
            }
            bottomBar
        }.padding(20)
    }
    // Source · record · engine · AI · code — one row of floating glass controls.
    private var controlBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                GlassChip(symbol: model.settings.effectiveAudioMode == .microphone ? "mic" : "speaker.wave.2", title: "Джерело · " + model.settings.effectiveAudioMode.label,
                          value: model.running ? model.captureSourceName : model.configuredSourceName,
                          accessory: AnyView(HStack(spacing: 3) {
                              if model.settings.effectiveAudioMode != .microphone { MiniMeter(level: model.systemLevel) }
                              if model.settings.effectiveAudioMode != .system { MiniMeter(level: model.micLevel) }
                          })) { CaptureSourceView(model: model).frame(width: 440) }
                    .frame(maxWidth: 300, alignment: .leading)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    RecordButton(model: model, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.running ? clock(model.sessionSeconds) : "Запис").font(.title2.weight(.semibold)).monospacedDigit()
                        Text(model.stopping ? "Завершую…" : model.starting ? "Запускаю…" : model.running ? "Слухаю" : "Натисніть, щоб почати").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 140, alignment: .leading)
                }
                Spacer(minLength: 8)
                if !warnings.isEmpty {
                    Label("\(warnings.count)", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 11).padding(.vertical, 9).glass(Capsule(), tint: .orange.opacity(0.35)).help(warnings.joined(separator: "\n"))
                }
                GlassChip(symbol: "waveform", title: "Розпізнавання", value: engineName, tone: StatusTone.of(model.whisperStatus)) { EnginePanel(model: model).frame(width: 340) }
                GlassChip(symbol: "cpu", title: "Модель AI", value: activeModel, tone: StatusTone.of(model.ollamaStatus)) { ModelPanel(model: model).frame(width: 340) }
                GlassChip(symbol: model.project.rootPath.isEmpty ? "folder.badge.plus" : "folder.fill", title: "Код",
                          value: model.project.rootPath.isEmpty ? "Не підключено" : URL(fileURLWithPath: model.project.rootPath).lastPathComponent) { ProjectPanel(project: model.project).frame(width: 340) }
            }
        }
    }
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Транскрипт", symbol: "text.quote") {
                if model.settings.effectiveAudioMode == .both && showTranscript {
                    Picker("", selection: $transcriptSource) { Text("Співрозмовник").tag(AudioSource.system); Text("Я").tag(AudioSource.microphone) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                Button { withAnimation(.snappy) { showTranscript.toggle() } } label: { Image(systemName: "chevron.down").rotationEffect(.degrees(showTranscript ? 0 : -90)) }
                    .buttonStyle(.borderless).help(showTranscript ? "Згорнути" : "Розгорнути")
            }
            if showTranscript {
                let source = model.settings.effectiveAudioMode == .microphone ? .microphone : (model.settings.effectiveAudioMode == .system ? .system : transcriptSource)
                TranscriptCard(confirmed: source == .system ? model.systemTranscript : model.microphoneTranscript,
                               interim: source == .system ? model.systemInterim : model.microphoneInterim)
                Text("Сірий текст — чернетка · \(model.decodeSeconds, specifier: "%.2f") с на фразу · \(model.transcriptCount) записів")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
        }.card().frame(height: showTranscript ? 230 : nil)
    }
    private var bottomBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Toggle(isOn: $model.settings.automatic) { Label("Авто", systemImage: "bolt.fill") }
                    .toggleStyle(.button).glassButton(prominent: model.settings.automatic).controlSize(.large)
                    .help("Автоматично відповідати на завершені питання")
                if model.settings.effectiveAudioMode != .system {
                    Button { model.toggleMySpeaking() } label: { Label(model.mySpeaking ? "Слухати" : "Я говорю", systemImage: model.mySpeaking ? "ear" : "mic.slash") }
                        .glassButton().controlSize(.large).disabled(!model.running).help("Пауза мікрофона, поки ви говорите (⌃⌥⌘M)")
                }
                HStack(spacing: 10) {
                    TextField("Запитайте що завгодно або натисніть ⌘↩ для останньої фрази…", text: $model.manualQuestion, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...4).onSubmit { model.generateManual() }
                    Button { model.generateManual() } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).frame(width: 22, height: 22) }
                        .glassButton(prominent: true).buttonBorderShape(.circle).help("Відповісти (⌃⌥⌘G)").keyboardShortcut(.return, modifiers: .command)
                }.padding(.leading, 18).padding(.trailing, 7).padding(.vertical, 7)
                .glass(Capsule(), interactive: true)
            }
        }
    }
}

struct EnginePanel: View {
    @ObservedObject var model: ConversationManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Розпізнавання голосу").font(.headline)
            Picker("", selection: $model.settings.speechEngine) {
                VStack(alignment: .leading) { Text("Whisper"); Text("Найточніший для української й IT-термінів").font(.caption).foregroundStyle(.secondary) }.tag("whisper")
                VStack(alignment: .leading) { Text("Parakeet v3"); Text("У 10+ разів швидший і легший, Neural Engine").font(.caption).foregroundStyle(.secondary) }.tag("parakeet")
            }.pickerStyle(.radioGroup).labelsHidden().disabled(model.running || model.starting || model.modelBusy)
            if model.settings.speechEngine == "parakeet" && !ParakeetRecognitionService.installed {
                Button("Завантажити Parakeet (~0.5 ГБ)") { Task { await model.downloadModel() } }.glassButton(prominent: true).disabled(model.modelBusy)
            }
            Label(model.whisperStatus, systemImage: "circle.fill").font(.caption).foregroundStyle(StatusTone.of(model.whisperStatus).color)
            if model.running { Text("Змінити рушій можна після зупинки запису.").font(.caption).foregroundStyle(.secondary) }
            Divider()
            SettingsLink { Label("Мова, терміни й моделі Whisper…", systemImage: "gearshape") }.buttonStyle(.link).font(.caption)
        }
    }
}

struct ModelPanel: View {
    @ObservedObject var model: ConversationManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Модель AI · Ollama").font(.headline)
            if model.models.isEmpty { Text("Ollama не знайдено або моделі не встановлені.").font(.caption).foregroundStyle(.secondary) }
            else {
                Picker("", selection: $model.settings.model) {
                    ForEach(model.models) { Text($0.name + "  ·  " + String(format: "%.1f ГБ", Double($0.size) / 1e9)).tag($0.name) }
                    if !model.models.contains(where: { $0.name == model.settings.model }) { Text(model.settings.model).tag(model.settings.model) }
                }.pickerStyle(.radioGroup).labelsHidden()
            }
            Toggle("Швидкий режим · \(model.settings.fastModel)", isOn: $model.settings.fastAnswers).help("Швидше, але може помилятися в коді")
            Toggle("Режим міркувань", isOn: $model.settings.thinking)
            Label(model.ollamaStatus, systemImage: "circle.fill").font(.caption).foregroundStyle(StatusTone.of(model.ollamaStatus).color)
            Divider()
            HStack {
                Button("Оновити список") { Task { await model.refreshModels() } }.glassButton()
                Spacer()
                SettingsLink { Label("Контекст і промпт…", systemImage: "gearshape") }.buttonStyle(.link).font(.caption)
            }
        }
    }
}

struct ProjectPanel: View {
    @ObservedObject var project: ProjectContextService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Папка з кодом").font(.headline)
            Text(project.rootPath.isEmpty ? "Підключіть папку проєкту — відповіді на питання про код спиратимуться на точні рядки." : project.rootPath)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if !project.rootPath.isEmpty { Label(project.status, systemImage: "doc.text.magnifyingglass").font(.caption) }
            HStack {
                Button(project.rootPath.isEmpty ? "Вибрати папку…" : "Змінити…") { project.chooseFolder() }.glassButton(prominent: project.rootPath.isEmpty)
                if !project.rootPath.isEmpty {
                    Button("Оновити") { Task { await project.refresh() } }.glassButton().disabled(project.busy)
                    Button("Від’єднати", role: .destructive) { project.connect("") }.glassButton()
                }
            }
        }
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
                Button { model.generateManual() } label: { Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).frame(width: 18, height: 18) }.glassButton(prominent: true).buttonBorderShape(.circle)
            }.padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6).glass(Capsule(), interactive: true)
            if !model.error.isEmpty { Label(model.error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(3).help(model.error) }
        }.padding(14).padding(.top, 14).frame(minWidth: 340, minHeight: 260)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous)).ignoresSafeArea().appColorScheme(model.settings.appearance)
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
                Button("Видалити все", role: .destructive) { confirmDelete = true }.glassButton().disabled(model.history.isEmpty)
            }
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Пошук у питаннях і відповідях", text: $search).textFieldStyle(.plain) }.padding(.horizontal, 14).padding(.vertical, 9).glass(Capsule(), interactive: true)
            if records.isEmpty {
                EmptyState(symbol: "clock", title: model.history.isEmpty ? "Історія порожня" : "Нічого не знайдено", hint: "Завершені відповіді зберігаються тут, якщо збереження історії увімкнено.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Продовжити") { model.restore(record) }.controlSize(.small).glassButton() }
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
                    Text("Рушій").foregroundStyle(.secondary)
                    Picker("", selection: $model.settings.audioBackend) { Text("Core Audio Tap · лише звук").tag("Core Audio Tap"); Text("ScreenCaptureKit").tag("ScreenCaptureKit") }
                        .pickerStyle(.segmented).labelsHidden().disabled(model.settings.audioMode == .microphone)
                        .onChange(of: model.settings.audioBackend) { Task { await model.refreshApplications() } }
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
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label(model.running ? model.captureSourceName : model.configuredSourceName, systemImage: "app.badge")
                Label(model.microphoneDeviceName + " · " + model.micStatus, systemImage: "mic")
                Label("Вихід: " + model.outputDeviceName, systemImage: "headphones")
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Власні терміни — у Налаштуваннях → Розпізнавання").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button { model.settings.privateWindow.toggle() } label: { Label(model.settings.privateWindow ? "Ghost ON" : "Ghost OFF", systemImage: model.settings.privateWindow ? "eye.slash" : "eye") }.glassButton().controlSize(.small)
            }
        }
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
