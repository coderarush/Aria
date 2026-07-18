import SwiftUI

/// Shared visual metrics for Aria's native Worklight language. These values are
/// deliberately small and semantic so desktop surfaces remain calm in both
/// macOS appearances and with every user-selected accent.
enum AriaVisualMetrics {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 12
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let smallRadius: CGFloat = 10
    static let cardRadius: CGFloat = 16
    static let sidebarWidth: CGFloat = 224
}

/// A material card with a restrained border and shadow. Content carries the
/// hierarchy; the treatment deliberately stays quieter than the Worklight.
struct AriaCard<Content: View>: View {
    var padding: CGFloat = AriaVisualMetrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AriaVisualMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AriaVisualMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
            .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }
}

/// A text-and-symbol status marker. Every status remains understandable without
/// relying on color alone.
struct AriaStatusBadge: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.11), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

/// A pane heading: a rounded display title and a quiet, functional subtitle.
struct PaneHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

/// A calm, centered empty state with a specific route back to useful work.
struct AriaEmptyState: View {
    let message: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            AppBlobMark(size: 84, animated: true)
                .opacity(0.85)
            Text(message)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            if let detail {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}
