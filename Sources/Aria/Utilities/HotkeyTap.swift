import AppKit
import Carbon.HIToolbox

/// Global hotkeys via a CGEvent tap — replaces the Carbon RegisterEventHotKey
/// path (suspected of corrupting Swift concurrency executor state on macOS
/// 26.3.x; the tap also consumes the keystroke so ⌥Space can't leak a space
/// into the focused app). Requires Accessibility trust, which Aria already
/// requests for computer use. Falls back gracefully (menu items still work)
/// when the tap can't be created.
@MainActor
final class HotkeyTap {
    nonisolated static let keySpace: Int64 = 49   // kVK_Space
    nonisolated static let keyD: Int64 = 2        // kVK_ANSI_D

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onTalk: () -> Void
    private let onType: () -> Void
    private let onDictate: () -> Void

    init(onTalk: @escaping () -> Void,
         onType: @escaping () -> Void,
         onDictate: @escaping () -> Void) {
        self.onTalk = onTalk
        self.onType = onType
        self.onDictate = onDictate
    }

    /// True when the tap is live. False = no Accessibility trust (or tap denied).
    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<HotkeyTap>.fromOpaque(userData).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: selfPtr) else {
            Log.trace("hotkeys: event tap unavailable (Accessibility not granted?) — menu items still work")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.trace("hotkeys: event tap live (⌥Space talk, ⌥⇧Space type)")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Runs on the main run loop (tap added to the main run loop). Consumes our
    /// combos; passes everything else through untouched. Re-enables the tap if
    /// the system disabled it (timeout under load).
    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.tapForReenable() { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // ⌥⇧D = system-wide dictation (talk → typed into the focused app).
        if code == Self.keyD {
            guard option, shift, !command, !control, !isRepeat else {
                return Unmanaged.passUnretained(event)
            }
            Task { @MainActor in Log.trace("hotkey: ⌥⇧D dictate"); self.onDictate() }
            return nil
        }

        guard code == Self.keySpace else { return Unmanaged.passUnretained(event) }
        // User-selectable modifier (Settings → Conversation): option (default)
        // or control — always Space, type panel = +shift.
        let wantControl = UserDefaults.standard.string(forKey: "app.hotkeyModifier") == "control"
        let primary = wantControl ? control : option
        let other = wantControl ? option : control
        guard primary, !command, !other else { return Unmanaged.passUnretained(event) }
        if !isRepeat {
            Task { @MainActor in
                Log.trace("hotkey: ⌥\(shift ? "⇧" : "")Space")
                if shift { self.onType() } else { self.onTalk() }
            }
        }
        return nil   // consume — no stray space reaches the focused app
    }

    private func tapForReenable() -> CFMachPort? { tap }
}
