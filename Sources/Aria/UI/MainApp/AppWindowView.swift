import SwiftUI
import AppKit

/// The full Aria app window (v1) — a Wispr-Flow-style home for everything the
/// floating orb does in the background: past conversations, recent activity,
/// connectors (scaffold), and a way into Settings.
///
/// Visual language matches `SettingsView`: a fixed left sidebar of icon rows and
/// a scrolling detail pane in grouped cards. Like SettingsView, this deliberately
/// avoids `NavigationSplitView` / `List` / `Form` — on macOS 26 those build a lazy
/// row list that trips the SwiftUI actor-isolation optimizer crash (see SettingsView's
/// header). A plain eager `HStack` sidebar gives the same native look without the risk.
@MainActor
struct AppWindowView: View {
    enum Section: String, CaseIterable, Identifiable {
        case conversations = "Conversations"
        case activity = "Activity"
        case connectors = "Connectors"
        case settings = "Settings"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .conversations: return "bubble.left.and.bubble.right"
            case .activity:      return "list.bullet.rectangle"
            case .connectors:    return "puzzlepiece.extension"
            case .settings:      return "gearshape"
            }
        }

        var subtitle: String {
            switch self {
            case .conversations: return "Everything you\u{2019}ve said to Aria, most recent first."
            case .activity:      return "A traceable log of every action Aria has taken."
            case .connectors:    return "Bring your tools into Aria. More are coming soon."
            case .settings:      return "Tune Aria\u{2019}s voice, behavior, and brain."
            }
        }
    }

    @State private var selection: Section = .conversations

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 215)

            Divider()

            ScrollView {
                detail
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .background(.background)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                AppWindowBlobMark(size: 22)
                Text("Aria").font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 2) {
                ForEach(Section.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.icon).frame(width: 18)
                            Text(section.rawValue)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selection == section ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        AppWindowHead(title: selection.rawValue, subtitle: selection.subtitle)
        switch selection {
        case .conversations: ConversationsPane()
        case .activity:      ActivityPane()
        case .connectors:    ConnectorsPane()
        case .settings:      SettingsPane()
        }
    }
}

// MARK: - Shared chrome (mirrors SettingsView's TabHead / SSection)

/// A detail-pane heading — title + subtitle, matching SettingsView's TabHead.
private struct AppWindowHead: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.bottom, 8)
    }
}

/// A grouped, titled card — the same material/rounding language as SettingsView's SSection.
private struct AppWindowCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title).font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary).textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

/// Aria's blob mark, drawn the same way as the menu-bar icon — a small brand
/// touch in the sidebar header. Tints to the accent color.
private struct AppWindowBlobMark: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: Self.blob(size: size))
            .resizable()
            .frame(width: size, height: size)
            .foregroundStyle(Color.accentColor)
    }

    private static func blob(size: CGFloat) -> NSImage {
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
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
            }
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - Conversations

private struct ConversationsPane: View {
    @State private var rows: [AppWindowModel.ConversationRow] = []
    @State private var selectedID: UUID?
    @State private var loaded = false

    private var selected: AppWindowModel.ConversationRow? {
        rows.first { $0.id == selectedID } ?? rows.first
    }

    var body: some View {
        AppWindowCard("History (\(rows.count))") {
            if rows.isEmpty {
                Text(loaded
                     ? "No conversations yet. Say \u{201C}Hey Aria\u{201D} and your chats will show up here."
                     : "Loading\u{2026}")
                    .foregroundStyle(.secondary).font(.callout)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // List of turns
                    VStack(spacing: 2) {
                        ForEach(rows) { row in
                            Button {
                                selectedID = row.id
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.snippet).font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(AppWindowModel.relativeTime(row.date))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background((selected?.id == row.id) ? Color.accentColor.opacity(0.14) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 280)

                    Divider().padding(.horizontal, 10)

                    // Detail of the selected turn
                    detailPane
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task {
            // ConversationMemory persists to a fixed JSON file and has no shared
            // singleton, so we open a fresh read-only instance that loads the same
            // on-disk turns. (Adaptation noted in the report.)
            let memory = ConversationMemory()
            let turns = await memory.turns
            rows = AppWindowModel.conversationRows(from: turns)
            selectedID = rows.first?.id
            loaded = true
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let row = selected {
            VStack(alignment: .leading, spacing: 12) {
                Text(row.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
                if !row.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(row.transcript).font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aria").font(.caption).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                    Text(row.response.isEmpty ? "\u{2014}" : row.response).font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            Text("Select a conversation.").foregroundStyle(.secondary).font(.callout)
        }
    }
}

// MARK: - Activity

private struct ActivityPane: View {
    @State private var entries: [ActivityEntry] = []
    @State private var loaded = false

    var body: some View {
        AppWindowCard("Recent actions (\(entries.count))") {
            if entries.isEmpty {
                Text(loaded ? "No actions recorded yet." : "Loading\u{2026}")
                    .foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(entries) { e in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(color(for: e.outcome)).frame(width: 8, height: 8).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(e.tool).font(.system(size: 13, weight: .semibold))
                                if !e.detail.isEmpty {
                                    Text(e.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            if !e.summary.isEmpty {
                                Text(e.summary).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                            }
                            Text(AppWindowModel.relativeTime(e.date))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Text(e.outcome.rawValue).font(.caption2).foregroundStyle(color(for: e.outcome))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if e.id != entries.last?.id { Divider() }
                }
            }
        }
        .task {
            entries = await ActivityLog.shared.recent(100)
            loaded = true
        }
    }

    private func color(for outcome: ActivityEntry.Outcome) -> Color {
        switch outcome {
        case .ok:       return .green
        case .failed:   return .orange
        case .declined: return .secondary
        }
    }
}

// MARK: - Connectors (v1 scaffold)

private struct ConnectorsPane: View {
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)]

    var body: some View {
        AppWindowCard("Integrations") {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(AppWindowModel.connectors) { connector in
                    ConnectorCard(connector: connector)
                }
            }
            Text("These are placeholders. Secure account connections are coming in a future release \u{2014} nothing is connected yet.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

private struct ConnectorCard: View {
    let connector: AppWindowModel.Connector

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: connector.icon)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                Text(connector.name).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            Button(connector.available ? "Connect" : "Coming soon") { }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!connector.available)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// MARK: - Settings entry

private struct SettingsPane: View {
    var body: some View {
        AppWindowCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open the full settings window to tune Aria\u{2019}s voice, conversation behavior, knowledge, agents, and more.")
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    NotificationCenter.default.post(name: .ariaOpenSettings, object: nil)
                } label: {
                    Label("Open Settings\u{2026}", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the app window's Settings pane to ask the AppDelegate to open
    /// the existing Settings window — reuse, never reimplement.
    static let ariaOpenSettings = Notification.Name("ariaOpenSettings")
}
