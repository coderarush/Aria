import AppKit

/// "Type to Aria" — a Raycast-grade command palette. ⌥⇧Space (or the menu)
/// summons a floating field with Aria's blob, your recent commands beneath
/// (↑/↓ to select, Enter to run, Esc to dismiss), in a soft popover material
/// with a spring-in entrance. Submits into the exact same conversation
/// pipeline as speech.
@MainActor
final class CommandInputPanel: NSPanel, NSTextFieldDelegate {

    private let onSubmit: (String) -> Void
    private let field = NSTextField()
    private let recentsStack = NSStackView()
    private var recents: [String] = []
    private var selected: Int = -1   // -1 = field text, 0.. = recents row

    private static let width: CGFloat = 620
    private static let rowHeight: CGFloat = 34

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 64),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        contentView = buildContent()
    }

    // MARK: layout

    private func buildContent() -> NSView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        // Header row: blob · field · esc hint
        let blob = NSImageView(image: Self.blobImage(size: 26))
        blob.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = "Ask Aria anything…"
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "esc")
        hint.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        recentsStack.orientation = .vertical
        recentsStack.alignment = .leading
        recentsStack.spacing = 2
        recentsStack.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(blob)
        container.addSubview(field)
        container.addSubview(hint)
        container.addSubview(divider)
        container.addSubview(recentsStack)

        NSLayoutConstraint.activate([
            blob.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            blob.topAnchor.constraint(equalTo: container.topAnchor, constant: 19),
            blob.widthAnchor.constraint(equalToConstant: 26),
            blob.heightAnchor.constraint(equalToConstant: 26),

            field.leadingAnchor.constraint(equalTo: blob.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: hint.leadingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: blob.centerYAnchor),

            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            hint.centerYAnchor.constraint(equalTo: blob.centerYAnchor),

            divider.topAnchor.constraint(equalTo: container.topAnchor, constant: 58),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            recentsStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            recentsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            recentsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])
        return container
    }

    /// One recents row: subtle return-arrow glyph + command text.
    private func makeRow(_ text: String, index: Int) -> NSView {
        let row = PaletteRow(text: text) { [weak self] in
            self?.submit(text)
        }
        row.isHighlighted = index == selected
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        return row
    }

    private func reloadRecents() {
        recents = RecentCommands.all()
        recentsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, cmd) in recents.enumerated() {
            let row = makeRow(cmd, index: i)
            recentsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: recentsStack.widthAnchor).isActive = true
        }
        let header: CGFloat = 64
        let listHeight = recents.isEmpty ? 0 : CGFloat(recents.count) * (Self.rowHeight + 2) + 18
        setContentSize(NSSize(width: Self.width, height: header + listHeight))
    }

    private func refreshSelection() {
        for (i, view) in recentsStack.arrangedSubviews.enumerated() {
            (view as? PaletteRow)?.isHighlighted = i == selected
        }
    }

    // MARK: presentation

    /// Show centered in the top third of the active screen with a soft
    /// spring-in (scale + fade), and focus the field.
    func present() {
        guard let screen = NSScreen.main else { return }
        selected = -1
        reloadRecents()
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2,
                               y: f.maxY - frame.height - f.height * 0.22))
        field.stringValue = ""
        alphaValue = 0
        contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.2, 0.36, 1)
            animator().alphaValue = 1
            contentView?.layer?.setAffineTransform(.identity)
        }
        field.becomeFirstResponder()
    }

    private func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        dismissAnimated()
        guard !trimmed.isEmpty else { return }
        RecentCommands.record(trimmed)
        onSubmit(trimmed)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismissAnimated() }

    // MARK: keyboard

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submit(selected >= 0 && selected < recents.count ? recents[selected] : field.stringValue)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissAnimated()
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !recents.isEmpty else { return true }
            selected = min(selected + 1, recents.count - 1)
            refreshSelection()
            return true
        case #selector(NSResponder.moveUp(_:)):
            selected = max(selected - 1, -1)
            refreshSelection()
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        // Typing returns focus to the field text.
        if selected != -1 { selected = -1; refreshSelection() }
    }

    /// Aria's blob outline rendered as a template-style icon for the palette.
    private static func blobImage(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let n = 11
            var pts: [CGPoint] = []
            for i in 0..<n {
                let a = CGFloat(i)
                let w = 0.6 * sin(0.6 + a * 0.9) + 0.3 * sin(1.02 + a * 1.7) + 0.1 * sin(0.3 + a * 2.3)
                let r = size * 0.42 * (1 + 0.10 * w)
                let ang = 2 * .pi * a / CGFloat(n) - .pi / 2
                pts.append(CGPoint(x: size / 2 + cos(ang) * r, y: size / 2 + sin(ang) * r))
            }
            let path = NSBezierPath()
            func pt(_ i: Int) -> CGPoint { pts[((i % n) + n) % n] }
            path.move(to: pt(0))
            for i in 0..<n {
                let p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2)
                path.curve(to: p2,
                           controlPoint1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                           controlPoint2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            }
            path.close()
            NSColor.labelColor.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// A hoverable, clickable recents row.
private final class PaletteRow: NSView {
    private let label = NSTextField(labelWithString: "")
    private let glyph = NSTextField(labelWithString: "↩")
    private let action: () -> Void

    var isHighlighted = false { didSet { refresh() } }
    private var hovered = false { didSet { refresh() } }

    init(text: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        glyph.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        glyph.textColor = .tertiaryLabelColor
        glyph.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        addSubview(label)
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { action() }

    private func refresh() {
        layer?.backgroundColor = (isHighlighted || hovered)
            ? NSColor.labelColor.withAlphaComponent(0.08).cgColor
            : NSColor.clear.cgColor
        label.textColor = (isHighlighted || hovered) ? .labelColor : .secondaryLabelColor
    }
}
