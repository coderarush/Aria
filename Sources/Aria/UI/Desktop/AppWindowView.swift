import SwiftUI
import Combine

/// Aria's main application window — a premium, branded home for everything she's
/// done. A materials sidebar (logo + sections) on the left, a scrolling content
/// pane on the right. Deliberately no NavigationSplitView / List / Form anywhere:
/// the codebase pins those off because SwiftUI's lazy row stacks crash the macOS
/// 26 optimizer (see SettingsView header). Everything here is eager VStack/HStack
/// inside ScrollView.
@MainActor
struct AppWindowView: View {
    @StateObject private var model = AppWindowModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .frame(minWidth: 900, minHeight: 600)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .ariaTaskStoreDidChange)) { _ in
            Task { await model.refreshCurrentTask() }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand lockup — the orb's own blob, scaled down.
            HStack(spacing: 11) {
                AppBlobMark(size: 30, animated: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aria")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Intelligence layer")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(AppSection.grouped) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(group.title, systemImage: group.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 2)
                        ForEach(group.sections) { section in
                            SidebarItem(section: section,
                                        isSelected: model.section == section,
                                        accent: settings.accentColor) {
                                select(section)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Footer status pill.
            AriaStatusBadge(title: "Aria is online", symbol: "checkmark.circle.fill", tint: .green)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(width: AriaVisualMetrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func select(_ section: AppSection) {
        if section == .settings {
            // Reuse the existing Settings window (separate effort owns its content).
            NotificationCenter.default.post(name: .ariaOpenSettings, object: nil)
            return
        }
        withAnimation(.easeOut(duration: 0.18)) { model.section = section }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.section {
        case .home:          HomePane(model: model)
        case .conversations: ConversationsPane(model: model)
        case .activity:      ActivityPane(model: model)
        case .receipts:      ReceiptsPane()
        case .insights:      InsightsPane()
        case .connectors:    ConnectorsPane()
        case .settings:      HomePane(model: model)   // settings opens its own window
        }
    }
}

// MARK: - Sidebar item

private struct SidebarItem: View {
    let section: AppSection
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 20)
                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16)
                          : (hovering ? Color.primary.opacity(0.06) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
