import SwiftUI

// MARK: - Home / Overview

/// The landing pane: a warm greeting, the breathing Aria hero, quick stats and
/// a few quick-action cards. The first thing the user sees — it should feel calm,
/// confident, and unmistakably Aria.
@MainActor
struct HomePane: View {
    @ObservedObject var model: AppWindowModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                stats
                quickActions
                Spacer(minLength: 8)
            }
            .padding(32)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hero: some View {
        AriaCard(padding: 26) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppWindowModel.greeting())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("I'm ready when you are. Say “Hey Aria”, press your hotkey, or pick up where we left off.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460, alignment: .leading)
                }
                Spacer(minLength: 0)
                AppBlobMark(size: 128, animated: true)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 16) {
            StatCard(icon: "bubble.left.and.bubble.right.fill",
                     value: "\(model.conversationCount)",
                     label: model.conversationCount == 1 ? "Conversation" : "Conversations",
                     tint: settings.accentColor)
            StatCard(icon: "checkmark.circle.fill",
                     value: "\(model.tasksCompleted)",
                     label: "Tasks done",
                     tint: Color(red: 0.25, green: 0.78, blue: 0.45))
            StatCard(icon: "bolt.fill",
                     value: "\(model.actionsTaken)",
                     label: "Actions taken",
                     tint: Color(red: 0.96, green: 0.70, blue: 0.20))
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 16) {
                QuickActionCard(icon: "bubble.left.and.bubble.right.fill",
                                title: "Conversations",
                                subtitle: "Revisit what you've asked",
                                tint: settings.accentColor) {
                    model.section = .conversations
                }
                QuickActionCard(icon: "list.bullet.rectangle.fill",
                                title: "Activity",
                                subtitle: "See everything Aria did",
                                tint: Color(red: 0.55, green: 0.40, blue: 0.95)) {
                    model.section = .activity
                }
                QuickActionCard(icon: "puzzlepiece.extension.fill",
                                title: "Connectors",
                                subtitle: "Hook up your apps",
                                tint: Color(red: 0.10, green: 0.70, blue: 0.67)) {
                    model.section = .connectors
                }
            }
        }
    }
}

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color
    var body: some View {
        AriaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [tint, tint.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? tint.opacity(0.45) : Color.primary.opacity(0.06),
                                  lineWidth: hovering ? 1.5 : 1))
            .shadow(color: .black.opacity(hovering ? 0.10 : 0.05),
                    radius: hovering ? 16 : 10, y: 5)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
    }
}

// MARK: - Conversations

@MainActor
struct ConversationsPane: View {
    @ObservedObject var model: AppWindowModel

    var body: some View {
        HStack(spacing: 0) {
            list
            Divider().opacity(0.5)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            // Search field.
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search conversations", text: $model.conversationQuery)
                    .textFieldStyle(.plain).font(.system(size: 13))
                if !model.conversationQuery.isEmpty {
                    Button { model.conversationQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.10)))
            .padding(14)

            Divider().opacity(0.5)

            if model.filteredConversations.isEmpty {
                AriaEmptyState(
                    message: model.conversationQuery.isEmpty ? "No conversations yet" : "No matches",
                    detail: model.conversationQuery.isEmpty
                        ? "Talk to Aria and your history will appear here."
                        : "Try a different search.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.filteredConversations) { row in
                            ConversationRowView(
                                row: row,
                                isSelected: model.selectedConversation?.id == row.id) {
                                model.selectedConversationID = row.id
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 320)
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder private var detail: some View {
        if let convo = model.selectedConversation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppWindowModel.relativeTime(convo.timestamp))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(convo.timestamp.formatted(date: .complete, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    ChatBubble(text: convo.transcript, isUser: true)
                    ChatBubble(text: convo.response, isUser: false)
                    Spacer(minLength: 0)
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            AriaEmptyState(message: "Select a conversation",
                           detail: "Pick a conversation on the left to read the full exchange.")
        }
    }
}

private struct ConversationRowView: View {
    let row: ConversationRow
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(row.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(AppWindowModel.relativeTime(row.timestamp))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text(row.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16)
                          : (hovering ? Color.primary.opacity(0.05) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct ChatBubble: View {
    let text: String
    let isUser: Bool
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? "You" : "Aria")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isUser ? Color.white.opacity(0.85) : .secondary)
                Text(text.isEmpty ? "—" : text)
                    .font(.system(size: 14))
                    .foregroundStyle(isUser ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background {
                if isUser {
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06)))
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Activity

@MainActor
struct ActivityPane: View {
    @ObservedObject var model: AppWindowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "Activity",
                           subtitle: "Every action Aria has taken, newest first.")
                if model.activityByDay.isEmpty {
                    AriaEmptyState(message: "Nothing here yet",
                                   detail: "When Aria sends mail, runs a task or touches your apps, it shows up here.")
                } else {
                    ForEach(model.activityByDay) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.id)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            AriaCard(padding: 6) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                                        if idx > 0 { Divider().opacity(0.4).padding(.leading, 46) }
                                        ActivityRowView(entry: entry)
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(32)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ActivityRowView: View {
    let entry: ActivityEntry

    private var icon: String {
        let t = entry.tool.lowercased()
        if t.contains("mail") || t.contains("email") { return "envelope.fill" }
        if t.contains("calendar") || t.contains("event") { return "calendar" }
        if t.contains("note") { return "note.text" }
        if t.contains("file") || t.contains("folder") || t.contains("download") { return "folder.fill" }
        if t.contains("web") || t.contains("url") || t.contains("browse") { return "globe" }
        if t.contains("app") || t.contains("open") || t.contains("quit") { return "app.dashed" }
        if t.contains("search") || t.contains("knowledge") { return "magnifyingglass" }
        if t.contains("brief") { return "newspaper.fill" }
        if t.contains("click") || t.contains("type") || t.contains("ui") { return "cursorarrow.rays" }
        return "bolt.fill"
    }

    private var outcomeTint: Color {
        switch entry.outcome {
        case .ok:       return Color(red: 0.25, green: 0.78, blue: 0.45)
        case .failed:   return Color(red: 0.95, green: 0.40, blue: 0.40)
        case .declined: return Color(red: 0.96, green: 0.70, blue: 0.20)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(outcomeTint)
                .frame(width: 34, height: 34)
                .background(outcomeTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(prettyTool(entry.tool))
                        .font(.system(size: 13.5, weight: .semibold))
                    Spacer(minLength: 6)
                    Text(AppWindowModel.relativeTime(entry.date))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize()
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                } else if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "send_mail" → "Send mail".
    private func prettyTool(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

// MARK: - Connectors

@MainActor
struct ConnectorsPane: View {
    var body: some View {
        // Eager rows of cards — deliberately NOT LazyVGrid/Grid, to stay in the
        // same crash-safe family as the rest of the window (no lazy row stacks).
        let rows = AppWindowModel.connectorCatalog.chunked(into: 3)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "Connectors",
                           subtitle: "Give Aria a way into the apps you live in. More arriving soon.")
                VStack(spacing: 16) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(row) { info in
                                ConnectorCard(info: info)
                            }
                            // Pad short final rows so cards keep their column width.
                            if row.count < 3 {
                                ForEach(0..<(3 - row.count), id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Array {
    /// Split into fixed-size chunks (for an eager card grid).
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private struct ConnectorCard: View {
    let info: ConnectorInfo
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: info.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: [info.tint, info.tint.opacity(0.72)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: info.tint.opacity(0.35), radius: 8, y: 4)
                Spacer(minLength: 0)
                statusPill
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name).font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(info.blurb)
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {} label: {
                Text(info.status == .connected ? "Manage" : "Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(info.status != .connected)
            .opacity(info.status == .connected ? 1 : 0.55)
            .help(info.status == .connected ? "" : "Coming soon")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hovering ? info.tint.opacity(0.4) : Color.primary.opacity(0.06),
                              lineWidth: hovering ? 1.5 : 1))
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.05), radius: hovering ? 18 : 12, y: 6)
        .scaleEffect(hovering ? 1.01 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hovering)
    }

    @ViewBuilder private var statusPill: some View {
        switch info.status {
        case .connected:
            pill(text: "Connected", color: Color(red: 0.25, green: 0.78, blue: 0.45), filled: true)
        case .comingSoon:
            pill(text: "Coming soon", color: .secondary, filled: false)
        }
    }

    private func pill(text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.14)))
    }
}
