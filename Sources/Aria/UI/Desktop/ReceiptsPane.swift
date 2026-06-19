import SwiftUI

/// Pure, view-independent presentation logic for the Receipts pane: relative-time
/// formatting and the importance → label / colour mapping. Lives here (not in the
/// view) so it can be unit-tested without a window — no SwiftUI state, every method
/// `nonisolated` and deterministic. The `Color` it returns is plain SwiftUI.Color
/// (a value type), so it stays Sendable-friendly.
enum ReceiptsFormat {

    /// The colour-coded pill label for an importance level.
    /// Routine ▸ neutral, Reversible ▸ blue (it can be taken back),
    /// Important ▸ amber (irreversible — the one that ever paused for you).
    static func importanceLabel(_ importance: ActionImportance) -> String {
        switch importance {
        case .routine:               return "Routine"
        case .reversible:            return "Reversible"
        case .importantIrreversible: return "Important"
        }
    }

    /// The pill tint for an importance level (SwiftUI.Color value — Sendable-safe).
    static func importanceColor(_ importance: ActionImportance) -> Color {
        switch importance {
        case .routine:               return Color(red: 0.55, green: 0.58, blue: 0.62)   // neutral grey
        case .reversible:            return Color(red: 0.26, green: 0.52, blue: 0.96)   // blue
        case .importantIrreversible: return Color(red: 0.93, green: 0.62, blue: 0.16)   // amber
        }
    }

    /// Compact relative time, e.g. "2m ago", "3h ago", "just now". Mirrors the
    /// window's existing `AppWindowModel.relativeTime` so receipts read the same as
    /// every other timestamp in the app.
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let secs = now.timeIntervalSince(date)
        if secs < 45 { return "just now" }
        if secs < 90 { return "1m ago" }
        if secs < 3600 { return "\(Int(secs / 60))m ago" }
        if secs < 5400 { return "1h ago" }
        if secs < 86_400 { return "\(Int(secs / 3600))h ago" }
        if secs < 172_800 { return "yesterday" }
        if secs < 604_800 { return "\(Int(secs / 86_400))d ago" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    /// "send_mail" → "Send mail" — a friendly tool name (matches ActivityRowView).
    static func prettyTool(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// "Receipts" — the full ledger of everything Aria did, newest first, with one-tap
/// undo for the reversible ones. This is the trust surface of high autonomy: nothing
/// happens unseen, and anything reversible can be taken back. Strictly read + undo:
/// it loads a snapshot from `ActionLedger.shared` (an actor — awaited) and never
/// mutates it except through the public `undo(id:)`. Eager VStack/HStack inside a
/// ScrollView — deliberately no List/Form/LazyVGrid (macOS 26 optimizer crash family,
/// see AppWindowView / SettingsView headers).
@MainActor
struct ReceiptsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var receipts: [ActionReceipt] = []
    @State private var loaded = false
    /// The id currently being undone, so its button shows a spinner + stays disabled.
    @State private var undoing: UUID?
    /// A transient banner shown when an undo fails (success just removes the row).
    @State private var undoError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "Receipts",
                           subtitle: "Everything Aria did, newest first. Undo the reversible ones any time.")
                if let undoError { errorBanner(undoError) }
                if receipts.isEmpty {
                    AriaEmptyState(
                        message: "Nothing yet",
                        detail: "Aria's actions will show up here, and you can undo the reversible ones.")
                } else {
                    AriaCard(padding: 6) {
                        VStack(spacing: 0) {
                            ForEach(Array(receipts.enumerated()), id: \.element.id) { idx, receipt in
                                if idx > 0 { Divider().opacity(0.4).padding(.leading, 46) }
                                ReceiptRowView(receipt: receipt,
                                               undoing: undoing == receipt.id) {
                                    undo(receipt)
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
        .task { if !loaded { await load() } }   // load once on first appear
    }

    /// Pull a fresh newest-first snapshot from the ledger actor.
    private func load() async {
        receipts = await ActionLedger.shared.recent(100)
        loaded = true
    }

    /// Reverse one receipt, then refresh from the source of truth. On failure, show
    /// a quiet banner and leave the row in place (the ledger keeps it).
    private func undo(_ receipt: ActionReceipt) {
        guard undoing == nil else { return }      // one at a time
        undoing = receipt.id
        undoError = nil
        Task {
            let result = await ActionLedger.shared.undo(id: receipt.id)
            if !result.success {
                undoError = result.output.isEmpty ? "Couldn't undo that." : result.output
            }
            receipts = await ActionLedger.shared.recent(100)
            undoing = nil
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.40))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(red: 0.95, green: 0.40, blue: 0.40).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Row

private struct ReceiptRowView: View {
    let receipt: ActionReceipt
    let undoing: Bool
    let onUndo: () -> Void

    private var pillColor: Color { ReceiptsFormat.importanceColor(receipt.importance) }
    private var pillLabel: String { ReceiptsFormat.importanceLabel(receipt.importance) }

    /// A glyph mirroring the Activity pane's tool→icon mapping, tinted by importance.
    private var icon: String {
        let t = receipt.tool.lowercased()
        if t.contains("mail") || t.contains("email") { return "envelope.fill" }
        if t.contains("calendar") || t.contains("event") { return "calendar" }
        if t.contains("note") { return "note.text" }
        if t.contains("file") || t.contains("folder") || t.contains("download") { return "folder.fill" }
        if t.contains("clipboard") || t.contains("copy") || t.contains("paste") { return "doc.on.clipboard" }
        if t.contains("web") || t.contains("url") || t.contains("browse") { return "globe" }
        if t.contains("app") || t.contains("open") || t.contains("quit") { return "app.dashed" }
        if t.contains("search") || t.contains("knowledge") { return "magnifyingglass" }
        if t.contains("click") || t.contains("type") || t.contains("ui") { return "cursorarrow.rays" }
        return "bolt.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(pillColor)
                .frame(width: 34, height: 34)
                .background(pillColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(receipt.summary.isEmpty ? ReceiptsFormat.prettyTool(receipt.tool) : receipt.summary)
                        .font(.system(size: 13.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(ReceiptsFormat.relativeTime(receipt.timestamp))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize()
                }
                HStack(spacing: 8) {
                    importancePill
                    Text(ReceiptsFormat.prettyTool(receipt.tool))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if receipt.canUndo { undoButton }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importancePill: some View {
        Text(pillLabel)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(pillColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(pillColor.opacity(0.14), in: Capsule())
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: 5) {
                if undoing {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(undoing ? "Undoing…" : "Undo")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(undoing)
        .opacity(undoing ? 0.7 : 1)
        .help("Undo this action.")
    }
}
