import SwiftUI
import AppKit
@main struct LocalCopilotApp: App {
    @StateObject private var model = ConversationManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Questionio", id: "main") {
            MainView(model: model).onAppear { delegate.configure(model) }
        }.defaultSize(width: 1100, height: 740)
        .commands { CommandGroup(after: .newItem) { Button("Generate Answer") { model.generateManual() }; Button("Floating Window") { model.togglePanel?() } } }
        Settings { SettingsView(model: model) }
        MenuBarExtra("Questionio", systemImage: model.running ? "waveform.circle.fill" : "waveform.circle") {
            MenuContent(model: model)
        }
    }
}
struct MenuContent: View {
    @ObservedObject var model: ConversationManager
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Questionio") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.stopping ? "Finishing speech…" : model.running ? "Stop listening" : "Start listening") { Task { if model.running { await model.stop() } else { await model.start() } } }.disabled(model.starting || model.stopping || model.modelBusy)
        Button("Generate Answer", action: model.generateManual)
        Button("Show / hide floating window") { model.togglePanel?() }
        Divider(); SettingsLink { Text("Settings…") }; Divider()
        Button("Quit Questionio") { NSApp.terminate(nil) }
    }
}
final class CopilotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // A click on a panel that is not key would only make it key: a pop-up such as the window list
    // would not open until the second click. Become key first, then handle the same click.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var hotkeys: HotkeyManager?
    private weak var model: ConversationManager?
    private var lastHotkeyEnabled: Bool?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); WindowPrivacyDiagnostics.removeOldTestImage() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func configure(_ model: ConversationManager) {
        guard self.model == nil else { applyPreferences(); return }; self.model = model
        model.togglePanel = { [weak self] in self?.togglePanel() }
        model.windowPreferencesChanged = { [weak self] in self?.applyPreferences() }
        model.resizePanel = { [weak self] extra in self?.resizePanel(by: extra) }
        model.panelMinimumHeight = { [weak self] height in
            guard let panel = self?.panel else { return }
            panel.minSize.height = height
            if panel.frame.height < height { self?.resizePanel(by: height - panel.frame.height) }
        }
        let hotkeys = HotkeyManager(); self.hotkeys = hotkeys
        hotkeys.action = { [weak model] key in
            guard let model else { return }
            switch key {
            case 1: model.generateManual()
            case 2: Task { if model.running { await model.stop() } else { await model.start() } }
            case 3: model.togglePanel?()
            case 4: model.toggleMySpeaking()
            default: break
            }
        }
        hotkeys.failure = { [weak model] in model?.diagnostics.log($0) }
        applyPreferences()
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: NSWindow.didBecomeKeyNotification, object: nil)
        // Also covers a window that appears without ever taking focus.
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }
    @objc private func windowChanged(_ notification: Notification) { applyPreferences() }
    func applyPreferences() {
        guard let model else { return }
        if let panel {
            if model.settings.alwaysOnTop {
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
            } else {
                panel.level = .normal
                panel.collectionBehavior = [.auxiliary, .fullScreenNone, .fullScreenDisallowsTiling]
            }
        }
        let sharing: NSWindow.SharingType = model.settings.privateWindow ? .none : .readOnly
        for window in NSApp.windows where window.sharingType != sharing { window.sharingType = sharing }
        if lastHotkeyEnabled != model.settings.hotkeysEnabled { lastHotkeyEnabled = model.settings.hotkeysEnabled; hotkeys?.setEnabled(model.settings.hotkeysEnabled) }
    }
    /// Grows downwards so the bar stays where the user put it, but not past the bottom of the screen.
    private func resizePanel(by extra: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let height = max(panel.minSize.height, frame.height + extra)
        frame.origin.y -= height - frame.height; frame.size.height = height
        if let bottom = panel.screen?.visibleFrame.minY, frame.minY < bottom { frame.origin.y = bottom }
        panel.setFrame(frame, display: true)
    }
    func togglePanel() {
        guard let model else { return }
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        if panel == nil {
            let panel = CopilotPanel(contentRect: NSRect(x: 240, y: 240, width: 560, height: 460), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Questionio · Notes"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            // Transparent window so the Liquid Glass panel refracts the desktop behind it.
            panel.titlebarAppearsTransparent = true; panel.titleVisibility = .hidden; panel.isOpaque = false; panel.backgroundColor = .clear; panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: FloatingView(model: model))
            panel.minSize = NSSize(width: 500, height: 140); panel.setFrameAutosaveName("QuestionioFloating")
            self.panel = panel
        }
        applyPreferences(); panel?.makeKeyAndOrderFront(nil)
        // Activating would pull the user out of a full-screen app's Space.
        if !model.settings.alwaysOnTop { NSApp.activate(ignoringOtherApps: true) }
    }
}
