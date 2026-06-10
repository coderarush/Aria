import AppKit

/// "Type to Aria" — a small floating text field for quiet rooms, meetings, and
/// anyone who'd rather type than talk (V9: voice AND text workflows). Enter
/// submits to the normal command pipeline; Escape dismisses.
@MainActor
final class CommandInputPanel: NSPanel, NSTextFieldDelegate {

    private let field = NSTextField()
    private let onSubmit: (String) -> Void

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 54),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .transient]

        field.placeholderString = "Ask Aria anything — Enter to send, Esc to close"
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        contentView = container
    }

    /// Show centered near the top of the active screen and focus the field.
    func present() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - 120))
        field.stringValue = ""
        makeKeyAndOrderFront(nil)
        field.becomeFirstResponder()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            orderOut(nil)
            if !text.isEmpty { onSubmit(text) }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        return false
    }
}
