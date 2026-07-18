import AppKit
import SwiftUI

/// The active half of the liquid body. It is deliberately separate from the
/// click-through IslandPanel: voice can show it without taking focus, while a
/// keyboard invocation makes this panel key and focuses its editor.
@MainActor
final class LiquidSurfacePanel: NSPanel {
    private let viewModel: IslandViewModel
    private let onSubmit: (String) -> Void
    private let onDismiss: () -> Void

    init(viewModel: IslandViewModel, onSubmit: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        super.init(contentRect: .init(x: 0, y: 0, width: 520, height: 220),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss() }

    func present(anchor: CGPoint, on screen: NSScreen?, focusEditor: Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        let layout = LiquidSurfaceLayout.make(anchor: anchor, visibleFrame: screen.visibleFrame,
                                              collapsedDiameter: AppSettings.shared.orbSize.diameter * AppSettings.shared.orbScale)
        setFrame(layout.panelFrame, display: false)
        let surface = LiquidSurfaceView(viewModel: viewModel, focusEditor: focusEditor,
                                        onSubmit: onSubmit, onDismiss: onDismiss)
        contentView = NSHostingView(rootView: surface)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.24, 1)
            animator().alphaValue = 1
        }
        if focusEditor { makeKeyAndOrderFront(nil) }
    }

    func dismissSurface() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.32
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.orderOut(nil); self?.alphaValue = 1 })
    }
}

private struct LiquidSurfaceView: View {
    @ObservedObject var viewModel: IslandViewModel
    let focusEditor: Bool
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    private var status: String {
        switch viewModel.liquidPhase {
        case .composing: return "Ask Aria"
        case .listening: return viewModel.isDictating ? "Dictating" : "Listening"
        case .working: return viewModel.workLabel.isEmpty ? "Working…" : viewModel.workLabel
        case .answering: return "Aria"
        case .error: return "Needs attention"
        case .ready: return "Aria"
        case .resting: return "Aria"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.62), viewModel.accent.opacity(0.46)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .shadow(color: viewModel.accent.opacity(0.24), radius: 28, y: 12)
            HStack(alignment: .top, spacing: 12) {
                LiquidBlobMark(accent: viewModel.accent, listening: viewModel.liquidPhase == .listening,
                               level: Double(viewModel.audioLevel))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 7) {
                    Text(status).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    content
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss Aria")
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aria liquid surface")
    }

    @ViewBuilder private var content: some View {
        switch viewModel.liquidPhase {
        case .composing:
            LiquidTextEditor(text: Binding(get: { viewModel.draftText }, set: viewModel.updateDraft),
                             focus: focusEditor, onSubmit: onSubmit, onEscape: onDismiss)
                .frame(minHeight: 30, maxHeight: 96)
        case .listening:
            Text(viewModel.draftText.isEmpty ? "Say what you need…" : viewModel.draftText)
                .font(.system(size: 17, weight: .medium)).textSelection(.enabled)
        case .working:
            ProgressView().controlSize(.small)
            Text(viewModel.workLabel).font(.system(size: 17, weight: .medium))
        case .answering, .error:
            Text(viewModel.responseHeadline.isEmpty ? viewModel.responseText : viewModel.responseHeadline)
                .font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        case .ready:
            Text(viewModel.cue?.text ?? "How can I help?").font(.system(size: 17, weight: .medium))
        case .resting:
            EmptyView()
        }
    }
}

private struct LiquidBlobMark: View {
    let accent: Color
    let listening: Bool
    let level: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: listening ? 1.0 / 30 : 1.0 / 12)) { timeline in
            let amp = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.09 + (listening ? level * 0.18 : 0)
            BlobShape(radii: BlobMath.radii(t: timeline.date.timeIntervalSinceReferenceDate, n: 11, amp: amp, speed: 0.8))
                .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(BlobShape(radii: BlobMath.radii(t: timeline.date.timeIntervalSinceReferenceDate, n: 11, amp: amp, speed: 0.8))
                    .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: .init(x: 0.32, y: 0.25), startRadius: 1, endRadius: 24)))
        }
    }
}

private struct LiquidTextEditor: NSViewRepresentable {
    @Binding var text: String
    let focus: Bool
    let onSubmit: (String) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let view = LiquidNSTextView()
        view.delegate = context.coordinator
        view.onSubmit = onSubmit
        view.onEscape = onEscape
        view.font = .systemFont(ofSize: 18)
        view.textColor = .labelColor
        view.backgroundColor = .clear
        view.drawsBackground = false
        view.isRichText = false
        view.isHorizontallyResizable = false
        view.textContainerInset = NSSize(width: 0, height: 0)
        view.textContainer?.widthTracksTextView = true
        DispatchQueue.main.async { if focus { view.window?.makeFirstResponder(view) } }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        if view.string != text { view.string = text }
        if focus { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: LiquidTextEditor
        init(_ parent: LiquidTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { parent.text = (notification.object as? NSTextView)?.string ?? "" }
    }
}

private final class LiquidNSTextView: NSTextView {
    var onSubmit: ((String) -> Void)?
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) { super.keyDown(with: event) }
            else { onSubmit?(string) }
        } else if event.keyCode == 53 { onEscape?() }
        else { super.keyDown(with: event) }
    }
}
