import Foundation
import Carbon.HIToolbox

/// Global push-to-talk hotkey via Carbon's RegisterEventHotKey — works without
/// Accessibility permission and coexists with the wake phrase (V9 constitution:
/// "wake phrase and push-to-talk must coexist"). Default: ⌥Space.
@MainActor
final class HotkeyManager {
    nonisolated static let defaultKeyCode: UInt32 = 49                  // kVK_Space
    nonisolated static let defaultModifiers: UInt32 = UInt32(optionKey) // ⌥

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Register the global hotkey. False if registration failed (e.g. the
    /// combination is taken by another app).
    @discardableResult
    func start(keyCode: UInt32 = HotkeyManager.defaultKeyCode,
               modifiers: UInt32 = HotkeyManager.defaultModifiers,
               id: UInt32 = 1) -> Bool {
        stop()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.onPress() }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef)
        guard installed == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x41524941) /* 'ARIA' */, id: id)
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
        if registered != noErr {
            Log.trace("hotkey: registration failed (\(registered)) — combination taken?")
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }
}
