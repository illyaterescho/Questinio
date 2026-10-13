import SwiftUI
import AppKit
import LocalCopilotCore

struct SessionContextView: View {
    @ObservedObject var model: ConversationManager
    @ObservedObject var screen: ScreenContextService
    init(model: ConversationManager) { self.model = model; screen = model.screen }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Контекст розмови й показаний код").font(.title2.bold())
            TextField("Тема, мова, умови задачі — наприклад React, захист лабораторної…", text: $model.sessionTopic).textFieldStyle(.roundedBorder)
            IDEContextView(editor: model.editor)
            ProjectContextView(project: model.project)
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Toggle("Знімок екрана / OCR", isOn: $screen.enabled); Spacer(); Button("Очистити") { screen.clear() } }
                    HStack {
                        Picker("Вікно", selection: $screen.selectedWindow) {
                            Text("Виберіть вікно з кодом…").tag(UInt32(0))
                            ForEach(screen.windows) { Text($0.title).tag($0.id) }
                            if screen.selectedWindow != 0 && !screen.windows.contains(where: { $0.id == screen.selectedWindow }) { Text("Вікно \(screen.selectedWindow) · оновіть список").tag(screen.selectedWindow) }
                        }
                        Button { Task { await screen.refreshWindows() } } label: { Image(systemName: "arrow.clockwise") }.help("Оновити вікна")
                    }
                    HStack {
                        Button("Зняти знімок") { Task { await screen.capture() } }
                        Button("Виділити область") { screen.selectRegion() }
                        if model.project.rootPath.isEmpty { Button("Відкрити код…") { screen.openCodeFile() } }
                    }.disabled(screen.busy)
                    HStack { Toggle("Оновлювати кожні 5 с і перед відповіддю", isOn: $screen.automatic); if screen.busy { ProgressView().controlSize(.small) } }
                    Toggle("Передавати знімок локальній Vision-моделі", isOn: $screen.useImage)
                    Text(screen.sourceName + " · " + screen.status).font(.caption).textSelection(.enabled)
                    if let updated = screen.updated { Text("Знімок: " + updated.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                    if let preview = screen.preview { Image(nsImage: preview).resizable().scaledToFit().frame(maxHeight: 140).accessibilityLabel("Попередній перегляд захопленого коду") }
                    Text("Код / OCR — можна вставити текст і виправити символи").font(.caption)
                    TextEditor(text: $screen.codeText).font(.system(.body, design: .monospaced)).frame(minHeight: 150).border(.quaternary)
                    Text("Папка лабораторної читається незалежно від знімка екрана. Знімки залишаються в RAM; OCR може помилятися в символах і відступах.").font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 390)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Пам’ять поточної сесії").font(.headline)
                    Text(model.summarizing ? "Стискаю попередні репліки…" : "Старі репліки стискаються у фоні; останні залишаються дослівно.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.memorySummary).frame(minHeight: 100, maxHeight: 180).border(.quaternary)
                    Text("Репліки з позначеним джерелом").font(.headline)
                    ScrollView { Text(model.sessionTranscript.isEmpty ? "Контекст з’явиться після завершених реплік. Нову сесію починає кнопка New session." : model.sessionTranscript).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(minHeight: 180)
                    Text("Пам’ять та код цієї сесії не відновлюються після закриття застосунку. Save history зберігає питання й відповіді окремо.").font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 250)
            }
        }.padding(20).task { if PermissionsManager.screenStatus == "Allowed" { await screen.refreshWindows() } }
    }
}
struct CompactCodeContext: View {
    @ObservedObject var screen: ScreenContextService
    var body: some View {
        HStack {
            Image(systemName: "text.viewfinder")
            Text(screen.enabled && (!screen.codeText.isEmpty || screen.preview != nil) ? "Код: " + screen.sourceName : "Код не підключений").lineLimit(1)
            Spacer()
            Button { Task { await screen.capture() } } label: { Image(systemName: "arrow.clockwise") }.disabled(screen.busy).help("Оновити показаний код")
            Toggle("Код", isOn: $screen.enabled).toggleStyle(.checkbox)
        }.font(.caption)
    }
}

struct ProjectContextView: View {
    @ObservedObject var project: ProjectContextService
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(project.rootPath.isEmpty ? "Вибрати папку лабораторної…" : "Змінити папку лабораторної…") { project.chooseFolder() }
                Button("Оновити файли") { Task { await project.refresh() } }.disabled(project.busy || project.rootPath.isEmpty)
                if !project.rootPath.isEmpty { Button("Від’єднати") { project.connect("") } }
                if project.busy { ProgressView().controlSize(.small) }
            }
            Text(project.rootPath.isEmpty ? project.status : project.rootPath + " · " + project.status).font(.caption).textSelection(.enabled)
            if !project.files.isEmpty {
                HStack {
                    Text("Пошук по всіх файлах папки").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Відкрити знайдене у WebStorm") { project.openSelectedInWebStorm() }.disabled(project.matches.isEmpty)
                }
                if !project.selectedFile.isEmpty { Text("Зараз відкрито: " + project.selectedFile).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Text("Questionio шукає потрібний код у всій папці й передає моделі релевантні рядки. Збережіть зміни в IDE, щоб оновився індекс.").font(.caption).foregroundStyle(.secondary)
                if !project.matches.isEmpty { Text("Знайдено: " + project.matches.joined(separator: ", ")).font(.caption).textSelection(.enabled) }
            }
        }.padding(8).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct IDEContextView: View {
    @ObservedObject var editor: IDEContextService
    var body: some View {
        HStack {
            Button(editor.enabled ? "Вимкнути читання WebStorm" : "Точне читання WebStorm…") { if editor.enabled { editor.disable() } else { editor.enable() } }
            Text(editor.status).font(.caption).textSelection(.enabled)
        }
    }
}
