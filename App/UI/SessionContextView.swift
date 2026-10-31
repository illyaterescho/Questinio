import SwiftUI
import AppKit
import LocalCopilotCore

struct SessionContextView: View {
    @ObservedObject var model: ConversationManager
    @ObservedObject var screen: ScreenContextService
    init(model: ConversationManager) { self.model = model; screen = model.screen }
    var body: some View {
        VStack(alignment: .leading, spacing: UI.gap) {
            Text("Контекст і код").font(.largeTitle.weight(.semibold))
            HStack { Image(systemName: "tag").foregroundStyle(.secondary); TextField("Тема, мова, умови задачі — наприклад React, співбесіда, нарада…", text: $model.sessionTopic).textFieldStyle(.plain) }.padding(.horizontal, 16).frame(height: UI.control + 6).glass(Capsule(), interactive: true)
            VStack(alignment: .leading, spacing: 10) {
                CardHeader("Папка проєкту", symbol: "folder") { IDEContextView(editor: model.editor) }
                ProjectContextView(project: model.project)
            }.card()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader("Показаний код", symbol: "text.viewfinder") { Toggle("Знімок / OCR", isOn: $screen.enabled).toggleStyle(.switch).controlSize(.mini); Button("Очистити") { screen.clear() }.controlSize(.small) }
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
                    TextEditor(text: $screen.codeText).font(.system(.body, design: .monospaced)).frame(minHeight: 150).scrollContentBackground(.hidden).padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Text("Папка проєкту читається незалежно від знімка екрана. Знімки залишаються в RAM; OCR може помилятися в символах і відступах.").font(.caption).foregroundStyle(.secondary)
                }.card().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader("Пам’ять сесії", symbol: "brain")
                    Text(model.summarizing ? "Стискаю попередні репліки…" : "Старі репліки стискаються у фоні; останні залишаються дослівно.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.memorySummary).frame(minHeight: 100, maxHeight: 180).scrollContentBackground(.hidden).padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    CardHeader("Репліки", symbol: "text.quote")
                    ScrollView { Text(model.sessionTranscript.isEmpty ? "Контекст з’явиться після завершених реплік. Нову сесію починає кнопка «Нова сесія»." : model.sessionTranscript).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(minHeight: 180)
                    Text(model.settings.saveHistory ? "Завершені репліки зберігаються локально в повному журналі. «Відновити останній» повертає текст і питання після перезапуску. Код перечитується з підключеної папки." : "Save history вимкнено: повний текст поточної сесії доступний для експорту до закриття застосунку.").font(.caption).foregroundStyle(.secondary)
                }.card().frame(width: 340).frame(maxHeight: .infinity, alignment: .top)
            }
        }.padding(UI.page).task { if PermissionsManager.screenStatus == "Allowed" { await screen.refreshWindows() } }
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
                Button(project.rootPath.isEmpty ? "Вибрати папку…" : "Змінити папку…") { project.chooseFolder() }
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
        }
    }
}

struct IDEContextView: View {
    @ObservedObject var editor: IDEContextService
    var body: some View {
        HStack {
            Text(editor.status).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(editor.status)
            Button(editor.enabled ? "Вимкнути WebStorm" : "Читати WebStorm…") { if editor.enabled { editor.disable() } else { editor.enable() } }.controlSize(.small)
        }
    }
}
