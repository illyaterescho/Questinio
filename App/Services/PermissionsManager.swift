import AVFoundation
import AppKit
import CoreGraphics
import LocalCopilotCore
@MainActor enum PermissionsManager {
    static var microphoneAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static func microphone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw CopilotError.message("Microphone permission was denied. Enable Questionio in System Settings → Privacy & Security → Microphone.") }
        default: throw CopilotError.message("Enable Questionio in System Settings → Privacy & Security → Microphone, then restart capture.")
        }
    }
    static var microphoneStatus: String { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "Allowed" : "Not granted" }
    static var screenStatus: String { CGPreflightScreenCaptureAccess() ? "Allowed" : "Not granted / macOS may ask for audio access" }
    static func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }
}
