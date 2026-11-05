import AppKit
import PDFKit
import UniformTypeIdentifiers
import LocalCopilotCore

/// Open panel that works from the non-activating floating panel: over a full-screen app a separate
/// dialog would open out of sight on another Space, while a sheet stays with the panel.
enum FilePicker {
    @MainActor static func choose(_ panel: NSOpenPanel, _ done: @escaping ([URL]) -> Void) {
        let finish = { (response: NSApplication.ModalResponse) in done(response == .OK ? panel.urls : []) }
        if let window = NSApp.keyWindow as? CopilotPanel { panel.beginSheetModal(for: window, completionHandler: finish) }
        else { finish(panel.runModal()) }
    }
}

struct StudyDocument: Identifiable, Equatable {
    let path: String
    var name: String { (path as NSString).lastPathComponent }
    var characters = 0
    var problem: String?
    var id: String { path }
}

/// Lab write-ups, explanations and notes the answers draw on. Text is extracted once, in the background.
@MainActor final class DocumentLibraryService: ObservableObject {
    @Published private(set) var documents: [StudyDocument] = []
    @Published private(set) var busy = false
    private(set) var index = DocumentIndex()
    var onPathsChanged: (([String]) -> Void)?
    private var texts: [String: String] = [:]
    private var loadID = UUID()
    static let types: [UTType] = [.init(filenameExtension: "docx"), .init(filenameExtension: "doc"), .pdf, .rtf, .plainText, .init(filenameExtension: "md"), .html].compactMap { $0 }

    func load(_ paths: [String]) {
        let paths = Array(NSOrderedSet(array: paths).array as? [String] ?? paths).prefix(20)
        documents = paths.map { StudyDocument(path: $0) }
        texts = texts.filter { paths.contains($0.key) }
        let missing = paths.filter { texts[$0] == nil }
        let id = UUID(); loadID = id; busy = !missing.isEmpty
        rebuild()
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            var found: [String: Result<String, Error>] = [:]
            for path in missing { found[path] = Result { try Self.extract(URL(fileURLWithPath: path)) } }
            await MainActor.run { [weak self] in
                guard let self, self.loadID == id else { return }
                for (path, result) in found { if case .success(let text) = result { self.texts[path] = text } }
                self.documents = self.documents.map { document in
                    var document = document
                    if case .failure(let error) = found[document.path] { document.problem = error.localizedDescription }
                    return document
                }
                self.busy = false; self.rebuild()
            }
        }
    }
    func add() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.allowedContentTypes = Self.types
        panel.message = "Лабораторні, пояснення, конспекти: Word, PDF, текст. Відповіді спиратимуться на них."
        FilePicker.choose(panel) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            let paths = self.documents.map(\.path) + urls.map(\.path)
            self.load(paths); self.onPathsChanged?(self.documents.map(\.path))
        }
    }
    func remove(_ document: StudyDocument) {
        load(documents.map(\.path).filter { $0 != document.path }); onPathsChanged?(documents.map(\.path))
    }
    /// Reads one file's text, e.g. a CV, without adding it to the materials.
    func importText(_ done: @escaping (String) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedContentTypes = Self.types
        FilePicker.choose(panel) { urls in
            guard let url = urls.first else { return }
            Task.detached(priority: .userInitiated) {
                let text = (try? Self.extract(url)) ?? ""
                await MainActor.run { if !text.isEmpty { done(String(text.prefix(8000))) } }
            }
        }
    }
    private func rebuild() {
        documents = documents.map { document in
            var document = document
            if let text = texts[document.path] { document.characters = text.count; document.problem = nil }
            else if !busy && document.problem == nil { document.problem = "Не прочитано" }
            return document
        }
        index = DocumentIndex(documents: documents.compactMap { document in texts[document.path].map { (document.name, $0) } })
    }
    nonisolated static func extract(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CopilotError.message("Файл не знайдено") }
        let text: String
        switch url.pathExtension.lowercased() {
        case "docx": text = try DocxText.text(fromDocx: url)
        case "pdf":
            guard let pdf = PDFDocument(url: url) else { throw CopilotError.message("PDF не відкривається") }
            text = pdf.string ?? ""
        case "doc", "rtf", "rtfd", "html", "htm", "odt": text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        default: text = try String(contentsOf: url, encoding: .utf8)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CopilotError.message("У файлі немає тексту (можливо, лише картинки)") }
        return String(trimmed.prefix(300_000))
    }
}
