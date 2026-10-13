import AppKit
import ApplicationServices
import LocalCopilotCore

struct EditorSnapshot {
    let window: String
    let relativePath: String?
    let text: String
    let cursorLine: Int?
    let visibleLine: Int?
    let symbol: String?
    var focusLine: Int? { visibleLine ?? cursorLine }
}
@MainActor final class IDEContextService: ObservableObject {
    @Published var enabled = false
    @Published var status = "WebStorm: точне читання вимкнено"
    @Published var file = ""
    @Published var cursorLine: Int?
    var onEnabledChanged: ((Bool) -> Void)?
    func enable() {
        enabled = true; onEnabledChanged?(true)
        if !AXIsProcessTrusted() {
            status = "Увімкніть Questionio у Accessibility та поверніться до застосунку"
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        }
    }
    func disable() { enabled = false; file = ""; cursorLine = nil; status = "WebStorm: точне читання вимкнено"; onEnabledChanged?(false) }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }; return value
    }
    private func string(_ element: AXUIElement, _ key: String) -> String { attribute(element, key) as? String ?? "" }
    func snapshot(root: String) -> EditorSnapshot? {
        guard enabled else { return nil }
        guard AXIsProcessTrusted() else { status = "Questionio не має дозволу Accessibility"; return nil }
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.jetbrains.WebStorm" }) else { status = "WebStorm не запущено"; return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { status = "У WebStorm немає відкритого вікна"; return nil }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        let title = string(window, kAXTitleAttribute)
        let start = Date(); var queue: [AXUIElement] = [window]; var offset = 0
        var editor: AXUIElement?; var breadcrumb: [String] = []
        if let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let candidate = unsafeBitCast(focused, to: AXUIElement.self)
            if string(candidate, kAXDescriptionAttribute).contains("Editor for") { editor = candidate }
        }
        // Only inspect the focused WebStorm window. Prune its project tree and
        // other tool windows; never traverse other applications or perform AX writes.
        while offset < queue.count && offset < 400 && Date().timeIntervalSince(start) < 1.5 {
            let element = queue[offset]; offset += 1
            let description = string(element, kAXDescriptionAttribute)
            if description.contains("Editor for") { editor = element }
            if description == "Navigation Bar", let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                breadcrumb = children.compactMap { child in
                    guard string(child, kAXRoleAttribute) == kAXButtonRole else { return nil }
                    let title = string(child, kAXTitleAttribute)
                    let description = string(child, kAXDescriptionAttribute)
                    return title.isEmpty ? (description.isEmpty ? nil : description) : title
                }
            }
            if description.contains("Project Tool Window") || description.contains("Project structure tree") || description.contains("Action Toolbar") { continue }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        guard let editor else { status = "Відкрийте текстовий файл у редакторі WebStorm"; return nil }
        let editorName = string(editor, kAXDescriptionAttribute).replacingOccurrences(of: "Editor for ", with: "")
        let text = string(editor, kAXValueAttribute)
        guard text.utf8.count <= 2_000_000 else { status = "Відкритий файл завеликий (понад 2 MB)"; return nil }
        var line: Int?
        var cursorOffset: Int?
        if let rangeValue = attribute(editor, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange(); let axRange = unsafeBitCast(rangeValue, to: AXValue.self)
            if AXValueGetValue(axRange, .cfRange, &range), range.location >= 0 {
                let length = min(range.location, (text as NSString).length)
                cursorOffset = length
                line = (text as NSString).substring(to: length).filter { $0 == "\n" }.count + 1
            }
        }
        var visibleLine: Int?
        if let rangeValue = attribute(editor, kAXVisibleCharacterRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange(); let axRange = unsafeBitCast(rangeValue, to: AXValue.self)
            if AXValueGetValue(axRange, .cfRange, &range), range.location >= 0, range.length > 0 {
                let end = min(range.location + range.length, (text as NSString).length)
                if end > range.location, cursorOffset == nil || cursorOffset! < range.location || cursorOffset! > end {
                    let middle = min(range.location + range.length / 2, end)
                    visibleLine = (text as NSString).substring(to: middle).filter { $0 == "\n" }.count + 1
                }
            }
        }
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = rootURL.pathComponents
        let rootIndex = breadcrumb.indices.first { index in
            Array(breadcrumb.prefix(index + 1)) == Array(rootComponents.suffix(index + 1))
        }
        guard let rootIndex else {
            status = "WebStorm: відкрийте файл із вибраної папки \(rootURL.lastPathComponent)"
            return nil
        }
        let fileIndex = breadcrumb.firstIndex { ProjectCodeIndex.extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        let matchesEditor = fileIndex.map { breadcrumb[$0] == editorName } ?? false
        let relative = matchesEditor && fileIndex != nil && fileIndex! > rootIndex ? breadcrumb[(rootIndex + 1)...fileIndex!].joined(separator: "/") : nil
        guard relative != nil else { status = "WebStorm: відкрийте файл із вибраної папки \(rootURL.lastPathComponent)"; return nil }
        let symbol = matchesEditor ? fileIndex.flatMap { index in index + 1 < breadcrumb.count ? breadcrumb[(index + 1)...].joined(separator: " / ") : nil } : nil
        file = relative ?? title; cursorLine = line
        status = "WebStorm: \(file)\(symbol.map { " · \($0)" } ?? "")\(visibleLine.map { " · видно біля рядка \($0)" } ?? line.map { " · курсор: рядок \($0)" } ?? "") · точний текст редактора"
        return EditorSnapshot(window: title, relativePath: relative, text: text, cursorLine: line, visibleLine: visibleLine, symbol: symbol)
    }
}
