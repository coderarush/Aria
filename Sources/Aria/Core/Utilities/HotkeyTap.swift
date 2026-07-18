import AppKit
import Carbon.HIToolbox

/// Detects a quick double-tap of the same trigger by timing successive taps.
/// Pure and testable: feed it timestamps, it tells you when a pair completes.
/// Consuming a pair resets state, so a triple-tap fires once (not twice).
struct DoubleTapDetector {
    let window: TimeInterval
    private var lastTap: Date?

    init(window: TimeInterval = 0.4) { self.window = window }

    /// Register a tap; returns true exactly when it completes a double-tap.
    mutating func registerTap(at time: Date = Date()) -> Bool {
        if let last = lastTap, time.timeIntervalSince(last) <= window {
            lastTap = nil            // consume the pair — next tap starts fresh
            return true
        }
        lastTap = time
        return false
    }
}

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
    nonisolated static let keyC: Int64 = 8        // kVK_ANSI_C

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onTalk: () -> Void
    private let onType: () -> Void
    private let onDictate: () -> Void
    private let onQuickCapture: () -> Void
    private let onLens: () -> Void

    // Double-tap-modifier state. Touched only inside `handle`, which runs on the
    // main run loop (the tap is added there), so this is single-threaded in practice.
    nonisolated(unsafe) private var quickTap = DoubleTapDetector(window: 0.4)
    nonisolated(unsafe) private var primaryHoldClean = false
    nonisolated(unsafe) private var lastFlags: CGEventFlags = []

    init(onTalk: @escaping () -> Void,
         onType: @escaping () -> Void,
         onDictate: @escaping () -> Void,
         onQuickCapture: @escaping () -> Void = {},
         onLens: @escaping () -> Void = {}) {
        self.onTalk = onTalk
        self.onType = onType
        self.onDictate = onDictate
        self.onQuickCapture = onQuickCapture
        self.onLens = onLens
    }

    /// True when the tap is live. False = no Accessibility trust (or tap denied).
    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue
                               | 1 << CGEventType.flagsChanged.rawValue)
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

    /// Temporarily enable/disable the live tap without tearing it down — used to
    /// freeze hotkeys while a blocking confirmation modal is open so a keystroke
    /// can't summon a second command on top of it.
    func setEnabled(_ on: Bool) {
        if let tap { CGEvent.tapEnable(tap: tap, enable: on) }
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
        // Bare modifier double-tap (⌥⌥) → quick capture. We only OBSERVE
        // flagsChanged and never consume it, so normal modifier use is untouched.
        if type == .flagsChanged {
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        // Any real key press invalidates an in-progress bare-modifier hold, so
        // ⌥Space (a combo) never counts as a bare ⌥ tap.
        primaryHoldClean = false
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

        // ⌥⇧C = Lens: circle anything on screen and Aria explains it.
        if code == Self.keyC {
            guard option, shift, !command, !control, !isRepeat else {
                return Unmanaged.passUnretained(event)
            }
            Task { @MainActor in Log.trace("hotkey: ⌥⇧C lens"); self.onLens() }
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

    /// Track press/release of the primary modifier alone and fire quick capture
    /// on a clean double-tap. "Clean" = the primary modifier is the sole modifier
    /// and no regular key was pressed during the hold.
    private nonisolated func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let mainMods: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let wantControl = UserDefaults.standard.string(forKey: "app.hotkeyModifier") == "control"
        let primaryMask: CGEventFlags = wantControl ? .maskControl : .maskAlternate

        let wasPrimary = lastFlags.contains(primaryMask)
        let nowPrimary = flags.contains(primaryMask)

        if nowPrimary {
            if !wasPrimary {
                // press edge — clean only if the primary modifier is alone
                primaryHoldClean = (flags.intersection(mainMods) == primaryMask)
            } else if flags.intersection(mainMods) != primaryMask {
                primaryHoldClean = false   // another modifier joined the hold
            }
        } else if wasPrimary {
            // release edge
            if primaryHoldClean, quickTap.registerTap(at: Date()) {
                Task { @MainActor in
                    Log.trace("hotkey: double-tap modifier → quick capture")
                    self.onQuickCapture()
                }
            }
            primaryHoldClean = false
        }
        lastFlags = flags
    }

    private func tapForReenable() -> CFMachPort? { tap }
}
