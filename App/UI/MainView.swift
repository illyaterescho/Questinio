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
            }.scrollContentBackground(.hidden).navigationTitle("Questionio").navigationSplitViewColumnWidth(min: 170, ideal: 190)
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
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(AmbientBackground()).frame(minWidth: 980, minHeight: 640).appColorScheme(model.settings.appearance)
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

/// One-line control inside the glass command bar; opens its own panel.
struct BarChip<Panel: View>: View {
    let symbol: String
    let value: String
    let help: String
    var tone: StatusTone?
    var maxWidth: CGFloat = 150
    var accessory: AnyView?
    @ViewBuilder var panel: Panel
    @State private var open = false
    @State private var hover = false
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .overlay(alignment: .topTrailing) { if let tone { Circle().fill(tone.color).frame(width: 6, height: 6).offset(x: 3, y: -2) } }
                Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail).frame(maxWidth: maxWidth, alignment: .leading)
                if let accessory { accessory }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 11).frame(height: 34)
            .background(.primary.opacity(open ? 0.12 : hover ? 0.07 : 0), in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain).onHover { hover = $0 }.help(help)
        .popover(isPresented: $open, arrowEdge: .bottom) { panel.padding(16) }
    }
}
struct MiniMeter: View {
    let level: Float
    var body: some View {
        let fill = min(1, Double(level) * 8)
        ZStack(alignment: .bottom) {
            Capsule().fill(.primary.opacity(0.1))
            Capsule().fill(fill > 0.8 ? Color.orange : Color.green).frame(height: max(3, 16 * fill)).animation(.easeOut(duration: 0.12), value: fill)
        }.frame(width: 4, height: 16)
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
    private var activeModel: String { model.answersUseClaude ? "Haiku 5.5" : model.settings.fastAnswers && model.models.contains(where: { $0.name == model.settings.fastModel }) ? model.settings.fastModel : model.settings.model }
    var body: some View {
        VStack(spacing: UI.gap) {
            controlBar
            if !model.error.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(model.error).font(.callout).lineLimit(3).textSelection(.enabled)
                    Spacer(minLength: 8)
                    IconButton(symbol: "xmark", help: "Закрити") { model.error = "" }
                }.foregroundStyle(.orange).padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
                .glass(RoundedRectangle(cornerRadius: UI.radius, style: .continuous), tint: .orange.opacity(0.2))
            }
            HStack(alignment: .top, spacing: UI.gap) {
                VStack(spacing: UI.gap) {
                    VStack(alignment: .leading, spacing: UI.inner) {
                        CardHeader("Питання", symbol: "questionmark.bubble") {
                            Text("\(model.questionInbox.entries.count)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                                .frame(minWidth: 24).frame(height: 22).padding(.horizontal, 4).background(.primary.opacity(0.07), in: Capsule())
                        }
                        QuestionInboxView(model: model)
                    }.card().frame(maxHeight: .infinity)
                    transcript
                }.frame(width: 360)
                AnswerCard(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            bottomBar
        }.padding(UI.page)
    }
    // Cluely-style command bar: one compact glass capsule centred above the content.
    private var controlBar: some View {
        HStack(spacing: 2) {
            RecordButton(model: model, size: UI.control)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.running ? clock(model.sessionSeconds) : "Запис").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text(model.stopping ? "Завершую…" : model.starting ? "Запускаю…" : model.running ? "Слухаю" : "⌃⌥⌘R").font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: 62, alignment: .leading).padding(.leading, 8)
            barDivider
            BarChip(symbol: model.settings.effectiveAudioMode == .microphone ? "mic" : "speaker.wave.2",
                    value: model.running ? model.captureSourceName : model.configuredSourceName,
                    help: "Джерело звуку · " + model.settings.effectiveAudioMode.label, maxWidth: 160,
                    accessory: AnyView(HStack(spacing: 2) {
                        if model.settings.effectiveAudioMode != .microphone { MiniMeter(level: model.systemLevel) }
                        if model.settings.effectiveAudioMode != .system { MiniMeter(level: model.micLevel) }
                    })) { CaptureSourceView(model: model).frame(width: 440) }
            BarChip(symbol: "waveform", value: engineName, help: "Розпізнавання · " + model.whisperStatus, tone: StatusTone.of(model.whisperStatus)) { EnginePanel(model: model).frame(width: 340) }
            BarChip(symbol: "cpu", value: activeModel, help: "Модель AI · " + model.ollamaStatus, tone: StatusTone.of(model.ollamaStatus), maxWidth: 130) { ModelPanel(model: model).frame(width: 340) }
            BarChip(symbol: model.project.rootPath.isEmpty ? "folder.badge.plus" : "folder", value: model.project.rootPath.isEmpty ? "Код" : URL(fileURLWithPath: model.project.rootPath).lastPathComponent,
                    help: "Папка з кодом", maxWidth: 120) { ProjectPanel(project: model.project).frame(width: 340) }
            barDivider
            if !warnings.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).frame(width: UI.control, height: UI.control).help(warnings.joined(separator: "\n"))
            }
            BarToggle(title: "Авто", symbol: "bolt.fill", isOn: $model.settings.automatic, help: "Автоматично відповідати на завершені питання")
        }.padding(6).frame(height: UI.bar).glass(Capsule())
        .frame(maxWidth: .infinity)
    }
    private var barDivider: some View { Divider().frame(height: 20).padding(.horizontal, 6) }
    private var transcript: some View {
        VStack(alignment: .leading, spacing: UI.inner) {
            CardHeader("Транскрипт", symbol: "text.quote") {
                if model.settings.effectiveAudioMode == .both && showTranscript {
                    Picker("", selection: $transcriptSource) { Text("Співрозмовник").tag(AudioSource.system); Text("Я").tag(AudioSource.microphone) }
                        .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 180)
                }
                IconButton(symbol: showTranscript ? "chevron.down" : "chevron.right", help: showTranscript ? "Згорнути" : "Розгорнути") { withAnimation(.snappy) { showTranscript.toggle() } }
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
    // One composer capsule: mic pause · question · Answer.
    private var bottomBar: some View {
        HStack(spacing: 8) {
            if model.settings.effectiveAudioMode != .system {
                IconButton(symbol: model.mySpeaking ? "mic.slash.fill" : "mic.fill", help: model.mySpeaking ? "Слухати мікрофон далі" : "Я говорю · пауза мікрофона (⌃⌥⌘M)") { model.toggleMySpeaking() }
                    .disabled(!model.running)
            } else {
                Image(systemName: "sparkles").foregroundStyle(.tint).frame(width: 28, height: 28)
            }
            TextField("Запитайте або натисніть «Відповісти» для останньої фрази", text: $model.manualQuestion, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...4).onSubmit { model.generateManual() }
            AccentButton(title: "Відповісти", shortcut: "⌘↩") { model.generateManual() }
                .keyboardShortcut(.return, modifiers: .command).help("Відповісти на останню фразу або введене питання (глобально ⌃⌥⌘G)")
        }.padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6).frame(minHeight: UI.bar)
        .glass(Capsule(), interactive: true)
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
            Text("Модель AI").font(.headline)
            ClaudeSection(model: model)
            Divider()
            Text("Ollama · локально").font(.subheadline.weight(.semibold))
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

/// Where the Anthropic API key goes. The key is stored only in the macOS Keychain.
struct ClaudeSection: View {
    @ObservedObject var model: ConversationManager
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: UI.inner) {
            Picker("Відповіді", selection: $model.settings.answerBackend) { Text("Claude Haiku").tag("claude"); Text("Ollama").tag("ollama") }.pickerStyle(.segmented)
            Picker("Фон", selection: $model.settings.backgroundBackend) { Text("Claude Haiku").tag("claude"); Text("Ollama").tag("ollama") }.pickerStyle(.segmented)
                .help("Класифікація реплік і стиснення пам’яті сесії")
            if model.claudeKeyStored {
                HStack {
                    Label("Ключ збережено в Keychain", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                    Spacer()
                    Button("Видалити", role: .destructive) { model.deleteClaudeKey() }.glassButton().controlSize(.small)
                }
            } else {
                HStack {
                    SecureField("Ключ Anthropic: sk-ant-…", text: $key).textFieldStyle(.roundedBorder).onSubmit { model.saveClaudeKey(key); key = "" }
                    Button("Зберегти") { model.saveClaudeKey(key); key = "" }.glassButton(prominent: true).disabled(key.isEmpty)
                }
                Text("Без ключа все працює локально через Ollama.").font(.caption).foregroundStyle(.secondary)
            }
            Stepper(String(format: "Денний ліміт: $%.2f", model.settings.claudeDailyLimitUSD), value: $model.settings.claudeDailyLimitUSD, in: 0.25...20, step: 0.25)
            Text(String(format: "Витрачено сьогодні: $%.4f", model.claudeSpentToday)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Toggle("Слати скриншоти в Claude (для питань про графіки)", isOn: $model.settings.claudeSendScreenshots)
            Text("З ключем в Anthropic ідуть текст розмови, фрагменти коду й OCR. Аудіо лишається на цьому Mac.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.task { await model.refreshClaudeSpend() }
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

/// Compact overlay: one glass bar (record · latest question · answer) and the answer card below.
struct FloatingView: View {
    @ObservedObject var model: ConversationManager
    @State private var showSource = false
    private var latest: String {
        if let entry = model.questionInbox.entries.last { return entry.text }
        return model.running ? "Слухаю…" : "Натисніть запис або ⌃⌥⌘R"
    }
    var body: some View {
        VStack(spacing: UI.inner) {
            HStack(spacing: 6) {
                RecordButton(model: model, size: UI.control)
                if model.running { Text(clock(model.sessionSeconds)).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary).padding(.leading, 2) }
                Text(latest).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.questionInbox.entries.isEmpty ? .secondary : .primary).help(latest).padding(.leading, 4)
                QuestionInboxView(model: model, compact: true).fixedSize()
                AccentButton(title: "Відповісти") { model.generateManual() }.disabled(model.generating).help("Відповісти на останнє питання (⌃⌥⌘G)")
                IconButton(symbol: "slider.horizontal.3", help: "Джерело звуку") { showSource.toggle() }
                    .popover(isPresented: $showSource) { CaptureSourceView(model: model).frame(width: 420).padding(16) }
                IconButton(symbol: model.settings.alwaysOnTop ? "pin.fill" : "pin", help: "Поверх інших вікон") { model.settings.alwaysOnTop.toggle() }
                    .disabled(model.settings.privateWindow)
            }.padding(6).frame(height: UI.bar).glass(Capsule())
            if !model.answer.isEmpty || model.generating || !model.question.isEmpty {
                AnswerCard(model: model, compact: true).transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 8) {
                TextField("Запитати…", text: $model.manualQuestion).textFieldStyle(.plain).font(.system(size: 13)).onSubmit { model.generateManual() }
                IconButton(symbol: "arrow.up.circle.fill", help: "Відповісти") { model.generateManual() }
            }.padding(.leading, 16).padding(.trailing, 6).frame(height: 40).glass(Capsule(), interactive: true)
            if !model.error.isEmpty { Label(model.error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2).help(model.error).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8) }
            Spacer(minLength: 0)
        }.padding(.horizontal, UI.inner).padding(.top, 28).padding(.bottom, UI.inner).frame(minWidth: 400, minHeight: 120)
        .animation(.snappy, value: model.answer.isEmpty && !model.generating)
        .ignoresSafeArea().appColorScheme(model.settings.appearance)
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
        VStack(alignment: .leading, spacing: UI.gap) {
            HStack {
                Text("Історія").font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Видалити все", role: .destructive) { confirmDelete = true }.glassButton().disabled(model.history.isEmpty)
            }
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Пошук у питаннях і відповідях", text: $search).textFieldStyle(.plain) }.padding(.horizontal, 16).frame(height: UI.control + 6).glass(Capsule(), interactive: true)
            if records.isEmpty {
                EmptyState(symbol: "clock", title: model.history.isEmpty ? "Історія порожня" : "Нічого не знайдено", hint: "Завершені відповіді зберігаються тут, якщо збереження історії увімкнено.")
            } else {
                ScrollView {
                    LazyVStack(spacing: UI.inner) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Продовжити") { model.restore(record) }.controlSize(.small).glassButton() }
                                Text(record.question).font(.headline).textSelection(.enabled)
                                Text(record.answer).foregroundStyle(.secondary).lineLimit(6).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                    }
                }
            }
        }.padding(UI.page)
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
