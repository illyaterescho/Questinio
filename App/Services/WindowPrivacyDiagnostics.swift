import AppKit
import ScreenCaptureKit
import LocalCopilotCore

@MainActor enum WindowPrivacyDiagnostics {
    /// Captures the panel's area with the panel and without it. Equal pictures mean capture cannot see the panel.
    /// Both pictures stay in memory. This covers ScreenCaptureKit only, not every sharing app.
    static func isVisibleInCapture() async throws -> Bool {
        guard let window = NSApp.windows.first(where: { $0 is CopilotPanel && $0.isVisible && $0.occlusionState.contains(.visible) }),
              let displayID = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let primary = NSScreen.screens.first else { throw CopilotError.message("Відкрийте плаваючу панель (⌃⌥⌘P) і не закривайте її іншими вікнами") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CopilotError.message("Дисплей панелі недоступний для захоплення") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // AppKit counts from the bottom-left of the primary screen; sourceRect from the top-left of the display.
        let frame = window.frame
        configuration.sourceRect = CGRect(x: frame.minX - display.frame.minX, y: primary.frame.height - frame.maxY - display.frame.minY, width: frame.width, height: frame.height)
        configuration.width = max(1, Int(frame.width)); configuration.height = max(1, Int(frame.height)); configuration.showsCursor = false
        let shown = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        window.orderOut(nil)
        defer { window.orderFrontRegardless() }
        try await Task.sleep(for: .milliseconds(300))
        let hidden = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CaptureComparison.differ(shown, hidden)
    }
    /// Older builds left a full-screen test picture here.
    static func removeOldTestImage() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("Questionio-window-privacy-test.png"))
    }
}
