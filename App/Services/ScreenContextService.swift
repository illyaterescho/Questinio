import AppKit
import ScreenCaptureKit
import Vision
import UniformTypeIdentifiers
import LocalCopilotCore

struct CodeWindow: Identifiable, Hashable { let id: UInt32; let title: String }
@MainActor final class ScreenContextService: ObservableObject {
    @Published var windows: [CodeWindow] = []
    @Published var selectedWindow: UInt32 = 0 { didSet { clearSnapshot(); region = nil; displayID = nil } }
    @Published var enabled = true
    @Published var automatic = false { didSet { configureTimer() } }
    @Published var useImage = true
    @Published var busy = false
    @Published var status = "Екран не захоплюється · виберіть вікно або область"
    @Published var sourceName = "Не вибрано"
    @Published var updated: Date?
    @Published var codeText = "" { didSet { if !updatingOCR { imageData = nil; preview = nil } } }
    @Published var preview: NSImage?
    private(set) var imageData: Data?
    private var updatingOCR = false
    private var region: CGRect?
    private var displayID: UInt32?
    private var timer: Task<Void, Never>?
    private var selectionPanel: NSPanel?
    private var epoch = UUID()
    func refreshWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            windows = content.windows.compactMap { window in
                guard window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier,
                      window.windowLayer == 0, window.frame.width > 100, window.frame.height > 60,
                      let title = window.title, !title.isEmpty else { return nil }
                return CodeWindow(id: window.windowID, title: (window.owningApplication?.applicationName ?? "App") + " · " + title)
            }.sorted { $0.title < $1.title }
        } catch { status = "Доступ до екрана: \(error.localizedDescription)"; automatic = false }
    }
    func openCodeFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.sourceCode, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 200000, let text = String(data: data, encoding: .utf8) else { throw CopilotError.message("Виберіть UTF-8 файл коду до 200 KB") }
            automatic = false; clearSnapshot(); codeText = String(text.prefix(20000)); sourceName = "Файл: " + url.lastPathComponent; status = "Код додано вручну"; enabled = true
        } catch { status = error.localizedDescription }
    }
    func clearSnapshot() {
        epoch = UUID(); updatingOCR = true; codeText = ""; updatingOCR = false
        imageData = nil; preview = nil; updated = nil
        status = "Знімок не зроблено"; sourceName = "Не вибрано"
    }
    func clear() { automatic = false; selectedWindow = 0; region = nil; displayID = nil; clearSnapshot() }
    private func configureTimer() {
        timer?.cancel(); timer = nil
        if automatic {
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    if self.enabled && !self.busy { await self.capture() }
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
        }
    }
    func selectRegion() {
        guard !busy, selectionPanel == nil, let screen = NSScreen.main else { return }
        let panel = CopilotPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.sharingType = .none
        let view = CodeRegionSelection(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.completed = { [weak self, weak panel] rectangle in
            panel?.orderOut(nil); self?.selectionPanel = nil
            guard let self, let rectangle, rectangle.width > 20, rectangle.height > 20 else { return }
            self.selectedWindow = 0; self.region = rectangle
            self.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            Task { await self.capture() }
        }
        panel.contentView = view; selectionPanel = panel; panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
    }
    func refreshForAnswer() async {
        while busy {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        await capture()
    }
    func capture() async {
        guard !busy, selectedWindow != 0 || region != nil else { status = "Спочатку виберіть вікно або область"; automatic = false; return }
        busy = true; defer { busy = false }
        let requestEpoch = epoch
        let windowID = selectedWindow; let selectedRegion = region; let selectedDisplay = displayID
        status = "Зчитування екрана…"
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let configuration = SCStreamConfiguration()
            let filter: SCContentFilter
            let size: CGSize
            let name: String
            if windowID != 0 {
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw CopilotError.message("Вибране вікно закрите. Виберіть його повторно.") }
                filter = SCContentFilter(desktopIndependentWindow: window); size = window.frame.size
                name = (window.owningApplication?.applicationName ?? "App") + " · " + (window.title ?? "Window")
            } else {
                guard let display = content.displays.first(where: { $0.displayID == selectedDisplay }), let rectangle = selectedRegion else { throw CopilotError.message("Екран від’єднаний. Виберіть область повторно.") }
                let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                configuration.sourceRect = rectangle; size = rectangle.size; name = "Область екрана \(display.displayID)"
            }
            let scale = min(2.0, 2400 / max(1, size.width), 1800 / max(1, size.height))
            configuration.width = max(1, Int(size.width * scale)); configuration.height = max(1, Int(size.height * scale))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let text = try await Task.detached(priority: .userInitiated) { try Self.recognize(image) }.value
            guard epoch == requestEpoch else { return }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { throw CopilotError.message("Не вдалося підготувати зображення") }
            updatingOCR = true; codeText = text; updatingOCR = false
            preview = NSImage(cgImage: image, size: size); imageData = jpeg; sourceName = name; updated = Date()
            status = text.isEmpty ? "Знімок готовий · OCR не знайшов текст; доступний Vision" : "Код оновлено · \(text.count) символів"
        } catch {
            guard epoch == requestEpoch else { return }
            status = "Екран: \(error.localizedDescription)"; automatic = false
            updatingOCR = true; codeText = ""; updatingOCR = false
            imageData = nil; preview = nil; updated = nil
        }
    }
    nonisolated static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["en-US", "uk-UA"].filter { supported.contains($0) }
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).sorted {
            if abs($0.boundingBox.minY - $1.boundingBox.minY) > 0.008 { return $0.boundingBox.minY > $1.boundingBox.minY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        let minX = lines.map { $0.boundingBox.minX }.min() ?? 0
        return String(lines.compactMap { line -> String? in
            guard let text = line.topCandidates(1).first?.string else { return nil }
            let charWidth = line.boundingBox.width / CGFloat(max(1, text.count))
            let indent = min(60, max(0, Int((line.boundingBox.minX - minX) / max(0.003, charWidth))))
            return String(repeating: " ", count: indent) + text
        }.joined(separator: "\n").prefix(20000))
    }
}
private final class CodeRegionSelection: NSView {
    var completed: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var end: NSPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); end = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { end = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        end = convert(event.locationInWindow, from: nil)
        guard let start, let end else { completed?(nil); return }
        completed?(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { completed?(nil) } else { super.keyDown(with: event) } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill(); bounds.fill()
        ("Виділіть код / задачу · Esc — скасувати" as NSString).draw(at: NSPoint(x: 30, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.white])
        guard let start, let end else { return }
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        NSColor.systemBlue.withAlphaComponent(0.2).setFill(); rect.fill()
        NSColor.systemBlue.setStroke(); let path = NSBezierPath(rect: rect); path.lineWidth = 3; path.stroke()
    }
}
