import AppKit
import ScreenCaptureKit
import LocalCopilotCore

@MainActor enum WindowPrivacyDiagnostics {
    static func capture() async throws -> URL {
        guard #available(macOS 14.0, *) else { throw CopilotError.message("Capture test requires macOS 14") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CopilotError.message("No display available") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width; configuration.height = display.height
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let data else { throw CopilotError.message("Cannot create test image") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Questionio-window-privacy-test.png")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}
