import SwiftUI
import AppKit
import LocalCopilotCore
struct SettingsView: View {
    @ObservedObject var model: ConversationManager
    @ObservedObject var diagnostics: DiagnosticsManager
    init(model: ConversationManager) { self.model = model; self.diagnostics = model.diagnostics }
    @State private var section = "General"
    private let sections: [(id: String, title: String, symbol: String)] = [("General", "Загальні", "gearshape"), ("Audio", "Звук", "speaker.wave.2"), ("Speech Recognition", "Розпізнавання", "waveform"), ("AI Models", "Моделі AI", "cpu"), ("Answer Behavior", "Відповіді", "text.bubble"), ("Appearance", "Вигляд", "paintpalette"), ("Hotkeys", "Гарячі клавіші", "keyboard"), ("Privacy", "Приватність", "lock.shield"), ("Diagnostics", "Діагностика", "stethoscope")]
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.id, selection: $section) { Label($0.title, systemImage: $0.symbol).tag($0.id) }.navigationSplitViewColumnWidth(200)
        } detail: {
            if section == "Diagnostics" { DiagnosticsView(model: model) }
            else {
                Form {
                    switch section {
                    case "General":
                        Section("Questionio") { Toggle("Автоматично відповідати на завершені питання", isOn: $model.settings.automatic); Toggle("Зберігати діалоги й відповіді локально", isOn: $model.settings.saveHistory); Text("Запис починається лише кнопкою. Розпізнавання працює в RAM; при затримці аудіо тимчасово йде в приватний кеш і видаляється після обробки. Текст зберігається лише з увімкненою історією.").font(.caption).foregroundStyle(.secondary) }
                    case "Audio":
                        Section("Джерела") {
                            Picker("Рушій системного звуку", selection: $model.settings.audioBackend) { Text("Core Audio Tap · лише звук").tag("Core Audio Tap"); Text("ScreenCaptureKit").tag("ScreenCaptureKit") }
                            Picker("Захоплення", selection: $model.settings.audioMode) { ForEach(AudioMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                            Picker("Мікрофон", selection: $model.settings.microphoneID) { Text("Системний").tag(UInt32(0)); ForEach(model.microphones) { Text($0.name).tag($0.id) } }
                            Picker("Програма-джерело", selection: $model.settings.applicationID) { Text("Усі програми (крім Questionio)").tag(""); ForEach(model.applications) { Text($0.name).tag($0.bundleID) }; if !model.settings.applicationID.isEmpty && !model.applications.contains(where: { $0.bundleID == model.settings.applicationID }) { Text(model.settings.applicationID).tag(model.settings.applicationID) } }
                            Button("Оновити список програм") { Task { await model.refreshApplications() } }
                            Toggle("Записувати мій мікрофон у режимі «Обидва»", isOn: $model.settings.captureMyVoice)
                            Toggle("Автовідповіді на питання з мікрофона", isOn: $model.settings.answerFromMicrophone)
                            Text("Після зміни джерела перезапустіть запис. AirPods з’являються, коли macOS показує їх як вхідний пристрій.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(model.running || model.starting || diagnostics.testing)
                        Section("Сигнал") { AudioMeter(label: "Мікрофон", level: model.micLevel, status: model.micStatus, symbol: "mic"); AudioMeter(label: "Звук програм", level: model.systemLevel, status: model.systemStatus, symbol: "speaker.wave.2") }
                    case "Speech Recognition":
                        Section("Whisper · офлайн") {
                            Text("Встановлена модель завантажується автоматично під час запуску.").font(.caption).foregroundStyle(.secondary)
                            Picker("Модель", selection: $model.settings.whisperVariant) { Text("Whisper Large v3 Turbo · найточніша").tag("openai_whisper-large-v3-v20240930_turbo"); Text("Whisper small · легша").tag("openai_whisper-small"); Text("Whisper base · найшвидша").tag("openai_whisper-base") }
                            TextField("Папка моделі", text: $model.settings.modelPath)
                            HStack { Button("Завантажити й увімкнути") { Task { await model.downloadModel() } }; Button("Увімкнути локальну") { Task { await model.loadModel() } }; Button("Вибрати папку…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK, let url = panel.url { model.settings.modelPath = url.path } } }
                            Text(model.whisperStatus).foregroundStyle(.secondary)
                            Text("Лише завантаження звертається до Hugging Face; далі все працює з локальних файлів. small займає кілька сотень МБ, Large v3 Turbo — близько 1.6 ГБ на диску й більше пам’яті.").font(.caption).foregroundStyle(.secondary)
                            Picker("Профіль термінів", selection: $model.settings.vocabularyProfile) { ForEach(SpeechVocabulary.profiles, id: \.self) { Text($0).tag($0) } }
                            TextField("Власні терміни: API, назви, терміни проєкту", text: $model.settings.customVocabulary, axis: .vertical).lineLimit(2...4)
                            Picker("Мова", selection: $model.settings.language) { Text("Автоматично").tag("auto"); Text("Українська").tag("uk"); Text("English").tag("en"); Text("Polski").tag("pl"); Text("Deutsch").tag("de"); Text("Français").tag("fr"); Text("Español").tag("es") }
                            LabeledContent("Пауза до підтвердження") { Slider(value: $model.settings.silenceSeconds, in: 0.5...2, step: 0.05); Text(String(format: "%.2f с", model.settings.silenceSeconds)).monospacedDigit() }
                            LabeledContent("Макс. фрагмент") { Slider(value: $model.settings.chunkSeconds, in: 4...12, step: 1); Text("\(Int(model.settings.chunkSeconds)) с") }
                            LabeledContent("Поріг голосу (VAD)") { Slider(value: $model.settings.vadThreshold, in: 0.002...0.04); Text(String(format: "%.3f", model.settings.vadThreshold)) }
                            Text("Енергетичний VAD, перекриття 0.5 с, не більше одного проміжного розпізнавання на вікно. Змінюйте, коли запис зупинено.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(model.running || model.starting || model.modelBusy || diagnostics.testing)
                    case "AI Models":
                        Section("Ollama · 127.0.0.1:11434") {
                            Picker("Модель", selection: $model.settings.model) { ForEach(model.models) { Text($0.name + " · " + String(format: "%.1f GB", Double($0.size) / 1e9)).tag($0.name) }; if !model.models.contains(where: { $0.name == model.settings.model }) { Text(model.settings.model).tag(model.settings.model) } }
                            Button("Оновити список моделей") { Task { await model.refreshModels() } }
                            Toggle("Режим міркувань (якщо модель підтримує)", isOn: $model.settings.thinking)
                            Text("Модель тримається в пам’яті під час запису й вивантажується через 15 хв простою. Одна генерація за раз, усе локально.").font(.caption).foregroundStyle(.secondary)
                            Picker("Контекст", selection: $model.settings.contextTokens) { Text("2048 токенів").tag(2048); Text("4096 токенів").tag(4096); Text("8192 токени").tag(8192); Text("16384 токени · більше пам’яті").tag(16384) }
                            Stepper("Бюджет тексту контексту: \(model.settings.contextCharacters) символів", value: $model.settings.contextCharacters, in: 2000...12000, step: 1000)
                        }
                    case "Answer Behavior":
                        Section("Стиль") { Toggle("Автовідповіді", isOn: $model.settings.automatic); LabeledContent("Температура") { Slider(value: $model.settings.temperature, in: 0...1); Text("\(model.settings.temperature, specifier: "%.2f")").monospacedDigit() }; Toggle("Повні відповіді · без ліміту токенів", isOn: Binding(get: { model.settings.maxTokens <= 0 }, set: { model.settings.maxTokens = $0 ? -1 : 2048 })); if model.settings.maxTokens > 0 { Stepper("Макс. токенів відповіді: \(model.settings.maxTokens)", value: $model.settings.maxTokens, in: 256...32768, step: 256) }; Text("Без ліміту генерація триває, доки модель не завершить або ви не натиснете «Стоп».").font(.caption).foregroundStyle(.secondary); Button("Стандартний стиль розробника") { model.settings.systemPrompt = CopilotSettings.developerPrompt }; Text("Системний промпт"); TextEditor(text: $model.settings.systemPrompt).font(.body).frame(height: 170).scrollContentBackground(.hidden).padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8)); Text("Автовиявлення питань підтримує українську й англійську; інші мови — для ручних питань.").font(.caption).foregroundStyle(.secondary) }
                    case "Appearance":
                        Section("Вікна") { Picker("Тема", selection: $model.settings.appearance) { Text("Як у системі").tag("system"); Text("Світла").tag("light"); Text("Темна").tag("dark") }.pickerStyle(.segmented); Toggle("Плаваюче вікно поверх інших", isOn: $model.settings.alwaysOnTop).disabled(model.settings.privateWindow); Text("Ghost mode keeps Notes above full-screen applications. In normal mode, Top applies only to regular desktop windows.").font(.caption).foregroundStyle(.secondary); Button("Показати / сховати плаваюче вікно") { model.togglePanel?() } }
                    case "Hotkeys":
                        Section("Глобальні клавіші") { Toggle("Увімкнути глобальні клавіші", isOn: $model.settings.hotkeysEnabled); LabeledContent("Відповісти", value: "⌃ ⌥ ⌘ G"); LabeledContent("Старт / стоп запису", value: "⌃ ⌥ ⌘ R"); LabeledContent("Плаваюче вікно", value: "⌃ ⌥ ⌘ P"); LabeledContent("Я говорю · пауза мікрофона", value: "⌃ ⌥ ⌘ M"); Text("Працюють через Carbon API, дозвіл Accessibility не потрібен. Конфлікти видно в Діагностиці.").font(.caption).foregroundStyle(.secondary) }
                    case "Privacy":
                        Section("Дані") { Toggle("Зберігати історію локально", isOn: $model.settings.saveHistory); Toggle("Request capture exclusion · experimental", isOn: $model.settings.privateWindow); Text("AppKit capture exclusion is requested, but full-display sharing may still show this window on modern macOS. This is not a guaranteed ghost mode. For reliable separation, share one application window or another display. Backlog audio uses private temporary files deleted after decoding; stale crash caches older than one day are cleaned on launch. No analytics or telemetry.").foregroundStyle(.secondary); Text("History: ~/Library/Application Support/LocalCopilot/history.sqlite\nDialogue: ~/Library/Application Support/LocalCopilot/Sessions/").font(.caption).textSelection(.enabled) }
                        Button("Test full-display capture exclusion") { Task { await model.testWindowPrivacy() } }.disabled(diagnostics.testing)
                        Section("Дозволи") { LabeledContent("Мікрофон", value: PermissionsManager.microphoneStatus); LabeledContent("Екран / системний звук", value: PermissionsManager.screenStatus); Button("Налаштування мікрофона") { PermissionsManager.openPrivacy("Privacy_Microphone") }; Button("Налаштування запису екрана й звуку") { PermissionsManager.openPrivacy("Privacy_ScreenCapture") } }
                    default: EmptyView()
                    }
                }.formStyle(.grouped).navigationTitle(sections.first(where: { $0.id == section })?.title ?? section)
            }
        }.frame(width: 840, height: 630).appColorScheme(model.settings.appearance)
    }
}
struct DiagnosticsView: View {
    @ObservedObject var model: ConversationManager
    @ObservedObject var diagnostics: DiagnosticsManager
    init(model: ConversationManager) { self.model = model; diagnostics = model.diagnostics }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Діагностика").font(.largeTitle.weight(.semibold))
            Text("Аудіотест слухає 5 секунд: говоріть у мікрофон або увімкніть звук у вибраній програмі. Аудіо не зберігається.").foregroundStyle(.secondary)
            HStack { Button("Тест мікрофона") { Task { await model.testAudio(.microphone) } }; Button("Тест системного звуку") { Task { await model.testAudio(.system) } }; Button("Тест Whisper · аудіофайл") { Task { await model.testWhisperFile() } }; Button("Тест Ollama") { Task { await diagnostics.testOllama(model.ollama, settings: model.settings) } } }.disabled(diagnostics.testing || model.running || model.starting || model.modelBusy || model.generating)
            if diagnostics.testing { ProgressView() }
            HStack(spacing: 20) { AudioMeter(label: "Мікрофон", level: model.micLevel, status: model.micStatus, symbol: "mic"); AudioMeter(label: "Звук програм", level: model.systemLevel, status: model.systemStatus, symbol: "speaker.wave.2") }.card(padding: 14)
            ScrollView { Text(diagnostics.lines.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.card(padding: 12)
            Text("Журнал зберігається лише в пам’яті. Мережа — тільки localhost і явні завантаження моделей.").font(.caption).foregroundStyle(.secondary)
        }.padding(22)
    }
}
