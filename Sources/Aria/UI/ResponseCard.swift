import SwiftUI

/// Frosted-glass card that floats above the orb and renders Aria's response.
/// Uses the platform AttributedString markdown parser for headers/bold/code/lists.
struct ResponseCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(attributed)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

/// SwiftUI wrapper over NSVisualEffectView for true frosted-glass material.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
