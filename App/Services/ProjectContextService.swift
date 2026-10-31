import AppKit
import LocalCopilotCore

@MainActor final class ProjectContextService: ObservableObject {
    @Published var rootPath = ""
    @Published var files: [ProjectCodeFile] = []
    @Published var selectedFile = ""
    @Published var followEditor = true
    @Published var status = "Папку проєкту не підключено"
    @Published var matches: [String] = []
    @Published var busy = false
    var onRootChanged: ((String) -> Void)?
    private var index = ProjectCodeIndex(files: [])
    private var epoch = UUID()
    private var refreshTask: Task<Void, Never>?
    var speechTerms: String {
        guard !files.isEmpty else { return "" }
        let active = files.first(where: { $0.path == selectedFile })
        let source = (active.map { $0.path + " " + String($0.text.prefix(12000)) } ?? "") + " " + files.prefix(200).map(\.path).joined(separator: " ")
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9_]{3,35}"#) else { return "" }
        let skipped: Set<String> = ["const", "return", "function", "export", "import", "private", "public", "string", "number", "this", "true", "false", "undefined", "class", "from", "component", "constructor"]
        var result: [String] = []; var seen: Set<String> = []
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source) else { continue }
            let term = String(source[range]); let key = term.lowercased()
            if skipped.contains(key) || !seen.insert(key).inserted { continue }
            result.append(term)
            if result.joined(separator: ", ").count > 700 { break }
        }
        return result.joined(separator: ", ")
    }
    func observe(_ editor: EditorSnapshot) {
        guard followEditor else { return }
        let path = editor.relativePath.flatMap { candidate in files.contains(where: { $0.path == candidate }) ? candidate : nil }
            ?? index.matchVisible(source: editor.window, visible: editor.text)
        if let path, path != selectedFile {
            selectedFile = path
            status = "\(files.count) файлів · активний: \(path)"
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = false
        panel.message = "Виберіть папку проєкту або лабораторної. Questionio читатиме код із цієї папки локально."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        connect(url.path)
    }
    func connect(_ path: String) {
        epoch = UUID(); rootPath = path; selectedFile = ""; files = []; index = ProjectCodeIndex(files: []); matches = []
        onRootChanged?(path); refreshTask?.cancel()
        guard !path.isEmpty else { status = "Папку проєкту не підключено"; return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }; await self.refresh()
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
            }
        }
    }
    func refresh() async {
        guard !rootPath.isEmpty, !busy else { return }
        let id = epoch; let path = rootPath; busy = true; defer { busy = false }
        do {
            let fresh = try await Task.detached(priority: .utility) { try ProjectCodeIndex.load(root: URL(fileURLWithPath: path)) }.value
            guard id == epoch else { return }
            index = fresh; files = fresh.files
            if !selectedFile.isEmpty && !files.contains(where: { $0.path == selectedFile }) { selectedFile = "" }
            status = "\(files.count) файлів · точні рядки з диска · оновлення кожні 8 с"
        } catch { guard id == epoch else { return }; index = ProjectCodeIndex(files: []); files = []; selectedFile = ""; status = error.localizedDescription }
    }
    func context(question: String, source: String, visible: String, editor: EditorSnapshot? = nil) -> CodeSearchResult {
        var currentIndex = index
        var source = source; var visible = visible
        if let editor {
            source = editor.window; visible = editor.text
            let path = editor.relativePath.flatMap { candidate in files.contains(where: { $0.path == candidate }) ? candidate : nil } ?? index.matchVisible(source: source, visible: visible)
            if let path {
                currentIndex = index.replacing(path: path, text: editor.text)
                visible = ""
                observe(editor)
            }
        }
        if followEditor && editor == nil {
            selectedFile = index.matchVisible(source: source, visible: visible) ?? ""
        }
        var query = question
        if ProjectCodeIndex.requestedLine(question) == nil, let line = editor?.focusLine,
           ["цей ряд", "цьому ряд", "ця функц", "цій функц", "цю стр", "цей стр"].contains(where: { question.lowercased().contains($0) }) { query += "\nПоточний рядок \(line)" }
        let compact = ProjectCodeIndex.requestedLine(question) != nil || ProjectCodeIndex.namedSymbol(question) != nil || ProjectCodeIndex.refersToCurrentCode(question)
        let result = currentIndex.search(question: query, active: selectedFile.isEmpty ? nil : selectedFile, visible: visible, focusLine: editor?.focusLine, focusedSymbol: editor?.symbol, budget: compact ? 2400 : 4800)
        matches = result.files
        status = "\(files.count) файлів · " + (selectedFile.isEmpty ? "пошук по всій папці" : "відкрито: " + selectedFile)
        return result
    }
    func openSelectedInWebStorm() {
        let file = followEditor ? (matches.first ?? (selectedFile.isEmpty ? nil : selectedFile)) : (selectedFile.isEmpty ? matches.first : selectedFile)
        guard let file, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.jetbrains.WebStorm") else { return }
        let url = URL(fileURLWithPath: rootPath).appendingPathComponent(file)
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
