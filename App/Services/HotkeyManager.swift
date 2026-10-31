import Carbon
import Foundation
@MainActor final class HotkeyManager {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    var action: ((UInt32) -> Void)?
    var failure: ((String) -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if status == noErr {
                let key = id.id
                let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in manager.action?(key) }
            }
            return noErr
        }, 1, &type, pointer, &handler)
    }
    func setEnabled(_ enabled: Bool) {
        for key in keys { UnregisterEventHotKey(key) }; keys.removeAll()
        guard enabled else { return }
        for (id, code) in [(UInt32(1), UInt32(kVK_ANSI_G)), (2, UInt32(kVK_ANSI_R)), (3, UInt32(kVK_ANSI_P)), (4, UInt32(kVK_ANSI_M))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: 0x4C434F50, id: id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { keys.append(ref) } else { failure?("Hotkey \(id) unavailable (OSStatus \(status)); another app may have registered it.") }
        }
    }
    deinit { for key in keys { UnregisterEventHotKey(key) }; if let handler { RemoveEventHandler(handler) } }
}
