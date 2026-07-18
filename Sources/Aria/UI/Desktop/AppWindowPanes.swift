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
                if let task = model.currentTask { TaskProgressCard(task: task) }
                runtimeStatus
                capabilities
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
        let focus = HomeFocusPresentation.from(task: model.currentTask, readiness: model.operationalReadiness)
        return AriaCard(padding: 26) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(focus.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(focus.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460, alignment: .leading)
                    Button(action: { perform(focus.action) }) {
                        Label(actionTitle(for: focus.action), systemImage: actionSymbol(for: focus.action))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityHint(actionHint(for: focus.action))
                }
                Spacer(minLength: 0)
                AppBlobMark(size: 128, animated: true)
            }
        }
    }

    private func perform(_ action: HomeFocusAction) {
        switch action {
        case .askAria:
            NotificationCenter.default.post(name: .ariaShowCommandPalette, object: nil)
        case .resumeTask:
            NotificationCenter.default.post(name: .ariaResumeTask, object: nil)
        case .openSetup:
            NotificationCenter.default.post(name: .ariaOpenSettings, object: nil)
        }
    }

    private func actionTitle(for action: HomeFocusAction) -> String {
        switch action {
        case .askAria: return "Ask Aria"
        case .resumeTask: return "Resume task"
        case .openSetup: return "Review access"
        }
    }

    private func actionSymbol(for action: HomeFocusAction) -> String {
        switch action {
        case .askAria: return "command"
        case .resumeTask: return "play.fill"
        case .openSetup: return "gearshape"
        }
    }

    private func actionHint(for action: HomeFocusAction) -> String {
        switch action {
        case .askAria: return "Opens the command palette."
        case .resumeTask: return "Shows a confirmation before restarting the saved task."
        case .openSetup: return "Opens settings for required access."
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

    private var runtimeStatus: some View {
        RuntimeStatusCard(rows: model.runtimeStatus)
    }

    private var capabilities: some View {
        OperationalReadinessCard(
            readiness: model.operationalReadiness,
            openSettings: { NotificationCenter.default.post(name: .ariaOpenSettings, object: nil) },
            openConnectors: { model.section = .connectors })
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

private struct TaskProgressCard: View {
    let task: TaskProgressSummary

    private var tone: Color {
        task.state == .running ? .green : .orange
    }

    private var symbol: String {
        task.state == .running ? "arrow.triangle.2.circlepath" : "arrow.clockwise.circle"
    }

    var body: some View {
        AriaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Task continuity", systemImage: symbol)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(task.value)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tone)
                }
                Text(task.goal)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tone)
                    Text(task.progress)
                        .font(.system(size: 12.5, weight: .medium))
                    if let nextStep = task.nextStep {
                        Divider().frame(height: 14)
                        Text("Next: \(nextStep)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(task.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if task.canResume {
                    Button {
                        NotificationCenter.default.post(name: .ariaResumeTask, object: nil)
                    } label: {
                        Label("Resume task", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityHint("Shows a confirmation before restarting the saved task.")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

private struct RuntimeStatusCard: View {
    let rows: [RuntimeStatusRow]

    var body: some View {
        AriaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Aria status", systemImage: "waveform.path.ecg")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Live")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if rows.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking this Mac…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 0) {
                            runtimeCells(vertical: false)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            runtimeCells(vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func runtimeCells(vertical: Bool) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 {
                if vertical {
                    Divider().opacity(0.45)
                } else {
                    Divider().opacity(0.45)
                }
            }
            RuntimeStatusCell(row: row)
                .frame(minWidth: vertical ? nil : 160, maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RuntimeStatusCell: View {
    let row: RuntimeStatusRow

    private var tone: Color {
        switch row.tone {
        case .positive: return .green
        case .neutral: return .secondary
        case .attention: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 28, height: 28)
                .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(row.value)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct OperationalReadinessCard: View {
    let readiness: OperationalReadiness?
    let openSettings: () -> Void
    let openConnectors: () -> Void

    var body: some View {
        AriaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Capabilities", systemImage: "checklist.checked")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let readiness, !readiness.needsSettings, !readiness.needsConnectors {
                        Text("Ready")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }

                if let readiness {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 0) {
                            readinessCells(readiness.rows, vertical: false)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            readinessCells(readiness.rows, vertical: true)
                        }
                    }
                    if readiness.needsSettings || readiness.needsConnectors {
                        HStack(spacing: 10) {
                            if readiness.needsSettings {
                                Button(action: openSettings) {
                                    Label("Review access", systemImage: "gearshape")
                                }
                            }
                            if readiness.needsConnectors {
                                Button(action: openConnectors) {
                                    Label("Connect apps", systemImage: "link")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking capabilities…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func readinessCells(_ rows: [OperationalReadinessRow], vertical: Bool) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 { Divider().opacity(0.45) }
            OperationalReadinessCell(row: row)
                .frame(minWidth: vertical ? nil : 135, maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OperationalReadinessCell: View {
    let row: OperationalReadinessRow

    private var tone: Color {
        switch row.tone {
        case .positive: return .green
        case .neutral: return .secondary
        case .attention: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 28, height: 28)
                .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(row.value)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
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
    @State private var statuses: [ConnectorID: ConnectorStatus] = [:]

    var body: some View {
        // Eager rows of cards — deliberately NOT LazyVGrid/Grid, to stay in the
        // same crash-safe family as the rest of the window (no lazy row stacks).
        let rows = AppWindowModel.connectorCatalog.chunked(into: 3)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "Connectors",
                           subtitle: "Give Aria a way into the apps you live in. OAuth-backed ones need a client ID you create once — add it on the card, then connect.")
                VStack(spacing: 16) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(row) { info in
                                ConnectorCard(info: info,
                                              live: info.connectorID.flatMap { statuses[$0] },
                                              onChange: { Task { await reload() } })
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
        .task { await reload() }
    }

    private func reload() async {
        let list = await ConnectorStore.shared.connectors()
        statuses = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
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
    var live: ConnectorStatus?
    var onChange: () -> Void = {}

    @State private var hovering = false
    @State private var busy = false
    @State private var showingSetup = false
    @State private var errorText: String?
    /// A non-blocking live proof for connected providers, e.g. "✓ linked".
    @State private var linkVerified = false

    /// Resolve the display status from the live backend snapshot (pure mapping).
    private var status: ConnectorInfo.Status {
        ConnectorSetup.status(connectorID: info.connectorID, live: live)
    }

    private var buttonLabel: String {
        switch status {
        case .connected:     return busy ? "Disconnecting…" : "Disconnect"
        case .available:     return busy ? "Connecting…" : "Connect"
        case .notConfigured: return "Add client ID"
        case .comingSoon:    return "Coming soon"
        }
    }

    /// The button is live for every OAuth status except "coming soon"; the
    /// not-configured case opens the setup sheet rather than connecting.
    private var buttonEnabled: Bool {
        guard !busy else { return false }
        return status != .comingSoon
    }

    private func handleTap() {
        guard let id = info.connectorID else { return }
        switch status {
        case .notConfigured:
            errorText = nil
            showingSetup = true
        case .available:
            connect(id)
        case .connected:
            disconnect(id)
        case .comingSoon:
            break
        }
    }

    private func connect(_ id: ConnectorID) {
        errorText = nil
        busy = true
        Task {
            do {
                try await ConnectorStore.shared.connect(id)
            } catch let error as ConnectorError {
                if case .notConfigured = error {
                    errorText = "Add a client ID first."
                    showingSetup = true
                }
            } catch is CancellationError {
                // User closed the browser / cancelled — quietly reset.
            } catch {
                errorText = "Couldn't connect. Try again."
            }
            busy = false
            onChange()
        }
    }

    private func disconnect(_ id: ConnectorID) {
        busy = true
        linkVerified = false
        Task {
            await ConnectorStore.shared.disconnect(id)
            busy = false
            onChange()
        }
    }

    /// Off the main path: ask the store for a valid token and, if present, show a
    /// tiny "✓ linked" proof. Never blocks the UI; failures just leave it hidden.
    private func verifyLink() {
        guard let id = info.connectorID, status == .connected else {
            linkVerified = false
            return
        }
        Task {
            let token = await ConnectorStore.shared.validAccessToken(id)
            linkVerified = (token != nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            title
            if status == .connected { connectedDetail }
            if let errorText { errorRow(errorText) }
            primaryButton
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
        .task(id: live?.isConnected) { verifyLink() }
        .sheet(isPresented: $showingSetup) {
            if let id = info.connectorID {
                ConnectorSetupSheet(connectorID: id, info: info) {
                    showingSetup = false
                    onChange()           // refresh status → card becomes "Ready"
                } onCancel: {
                    showingSetup = false
                }
            }
        }
    }

    private var header: some View {
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
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.name).font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(info.blurb)
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Connected-account hint + the live "✓ linked" proof.
    @ViewBuilder private var connectedDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let live, let hint = ConnectorSetup.connectedHint(live) {
                Text(hint)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if linkVerified {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10.5))
                    Text("linked")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.25, green: 0.78, blue: 0.45))
            }
        }
    }

    private func errorRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.40))
    }

    private var primaryButton: some View {
        Button { handleTap() } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                }
                Text(buttonLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(buttonBackground,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!buttonEnabled)
        .opacity(buttonEnabled ? 1 : 0.55)
        .help(helpText)
    }

    private var buttonBackground: Color {
        switch status {
        case .connected:     return info.tint.opacity(0.16)
        case .notConfigured: return info.tint.opacity(0.16)
        default:             return Color.primary.opacity(0.06)
        }
    }

    private var helpText: String {
        switch status {
        case .notConfigured: return "Paste a \(info.name) OAuth client ID to get ready."
        case .available:     return "Open \(info.name) in your browser to connect."
        case .connected:     return "Remove Aria's access to \(info.name)."
        case .comingSoon:    return "Coming soon."
        }
    }

    @ViewBuilder private var statusPill: some View {
        switch status {
        case .connected:
            pill(text: ConnectorSetup.pillLabel(for: status),
                 color: Color(red: 0.25, green: 0.78, blue: 0.45), filled: true)
        case .available:
            pill(text: ConnectorSetup.pillLabel(for: status),
                 color: Color(red: 0.26, green: 0.52, blue: 0.96), filled: false)
        case .notConfigured:
            pill(text: ConnectorSetup.pillLabel(for: status),
                 color: Color(red: 0.93, green: 0.62, blue: 0.16), filled: false)
        case .comingSoon:
            pill(text: ConnectorSetup.pillLabel(for: status), color: .secondary, filled: false)
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

// MARK: - Client-ID setup sheet

/// An inline sheet to paste an OAuth client ID (and, for Notion/Slack, a client
/// secret). On save, both credentials are written to the Keychain via
/// `KeychainManager` — never UserDefaults, never logged — and `onSaved` fires so
/// the card refreshes to "Ready". Includes a short "how do I get a client ID?"
/// disclosure with the real per-provider steps.
@MainActor
private struct ConnectorSetupSheet: View {
    let connectorID: ConnectorID
    let info: ConnectorInfo
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showingHelp = false
    @State private var saveError: String?

    private var needsSecret: Bool { ConnectorSetup.requiresSecret(connectorID) }
    private var canSave: Bool {
        ConnectorSetup.canSave(connectorID, clientID: clientID, secret: clientSecret)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [info.tint, info.tint.opacity(0.72)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect \(info.name)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Paste the OAuth credentials from your own \(ConnectorSetup.consoleName(for: connectorID)).")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Fields
            VStack(alignment: .leading, spacing: 12) {
                field(title: "Client ID", text: $clientID,
                      prompt: "1234…apps.googleusercontent.com", secure: false)
                if needsSecret {
                    field(title: "Client Secret", text: $clientSecret,
                          prompt: "Your app's client secret", secure: true)
                }
            }

            // Help disclosure
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingHelp.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showingHelp ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("How do I get a client ID?")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showingHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(ConnectorSetup.setupSteps(for: connectorID).enumerated()),
                                id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 7) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(info.tint)
                                    .frame(width: 14, alignment: .trailing)
                                Text(step)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.40))
            }

            // Actions
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button { save() } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(canSave ? info.tint : Color.secondary.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func field(title: String, text: Binding<String>,
                       prompt: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary).textCase(.uppercase)
            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    /// Persist credentials to the Keychain, then notify. Secrets never go to
    /// UserDefaults and are never logged.
    private func save() {
        guard canSave else { return }
        let id = ConnectorSetup.sanitize(clientID)
        do {
            try KeychainManager.save(id, account: ConnectorSetup.clientIDAccount(connectorID))
            if needsSecret {
                let secret = ConnectorSetup.sanitize(clientSecret)
                try KeychainManager.save(secret,
                                         account: ConnectorSetup.clientSecretAccount(connectorID))
            }
            onSaved()
        } catch {
            saveError = "Couldn't save to Keychain. Please try again."
        }
    }
}
