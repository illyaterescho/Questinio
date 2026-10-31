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
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var hotkeys: HotkeyManager?
    private weak var model: ConversationManager?
    private var lastHotkeyEnabled: Bool?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func configure(_ model: ConversationManager) {
        guard self.model == nil else { applyPreferences(); return }; self.model = model
        model.togglePanel = { [weak self] in self?.togglePanel() }
        model.windowPreferencesChanged = { [weak self] in self?.applyPreferences() }
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: NSWindow.didBecomeKeyNotification, object: nil)
    }
    @objc private func spaceChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, let panel = self.panel, panel.isVisible, let model = self.model else { return }
            model.diagnostics.log("Notes Space check: ghost=\(model.settings.privateWindow), onActiveSpace=\(panel.isOnActiveSpace), level=\(panel.level.rawValue)")
        }
    }
    @objc private func windowChanged(_ notification: Notification) { applyPreferences() }
    func applyPreferences() {
        guard let model else { return }
        if let panel {
            if model.settings.privateWindow {
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
            } else {
                panel.level = model.settings.alwaysOnTop ? .floating : .normal
                panel.collectionBehavior = [.auxiliary, .fullScreenNone, .fullScreenDisallowsTiling]
            }
        }
        for window in NSApp.windows { window.sharingType = model.settings.privateWindow ? .none : .readOnly }
        if lastHotkeyEnabled != model.settings.hotkeysEnabled { lastHotkeyEnabled = model.settings.hotkeysEnabled; hotkeys?.setEnabled(model.settings.hotkeysEnabled) }
    }
    func togglePanel() {
        guard let model else { return }
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        if panel == nil {
            let panel = CopilotPanel(contentRect: NSRect(x: 240, y: 240, width: 470, height: 430), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Questionio · Notes"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: FloatingView(model: model))
            panel.minSize = NSSize(width: 340, height: 280); panel.setFrameAutosaveName("QuestionioFloating")
            self.panel = panel
        }
        applyPreferences(); panel?.makeKeyAndOrderFront(nil)
        if !model.settings.privateWindow { NSApp.activate(ignoringOtherApps: true) }
    }
}
