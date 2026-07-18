import SwiftUI

/// "What Aria's learned" — surfaces the on-device routines she's noticed and the
/// proactive nudges she's offered, so the user can see (and trust) the proactive
/// engine. Strictly read-only: it loads a fresh PatternEngine / ProactiveStore
/// snapshot from disk and never mutates them. All list shaping is pure + tested.
enum InsightsModel {

    struct LearnedRoutineRow: Identifiable, Equatable {
        let id: UUID
        let summary: String
        let confidence: Double
        let confidenceLabel: String
        let statusLabel: String
    }

    struct NudgeRow: Identifiable, Equatable {
        let id: String
        let title: String
        let source: SuggestionSource?
        let tally: String
        let verdict: NudgeVerdict
        let lastDismiss: Date?
    }

    enum NudgeVerdict: String, Equatable { case welcomed, mixed, backedOff }

    /// Below this, a pattern is "still just an observation" — not worth showing.
    static let displayConfidenceFloor = 0.70

    static func learnedRoutineRows(from patterns: [BehaviorPattern]) -> [LearnedRoutineRow] {
        patterns
            .filter { $0.status != .suppressed }
            .filter { $0.confidence >= displayConfidenceFloor }
            .sorted { $0.confidence > $1.confidence }
            .map { p in
                LearnedRoutineRow(id: p.id, summary: p.description, confidence: p.confidence,
                                  confidenceLabel: confidencePercent(p.confidence),
                                  statusLabel: statusLabel(for: p.status))
            }
    }

    static func confidencePercent(_ c: Double) -> String {
        "\(Int((min(max(c, 0), 1) * 100).rounded()))%"
    }

    static func statusLabel(for status: PatternStatus) -> String {
        switch status {
        case .observing:  return "Learning"
        case .suggested:  return "Suggested"
        case .approved:   return "Active"
        case .running:    return "Running"
        case .paused:     return "Paused"
        case .suppressed: return "Dismissed"
        }
    }

    static func nudgeRows(from store: ProactiveStore, now: Date) -> [NudgeRow] {
        store.feedback
            .filter { $0.value.accepts + $0.value.dismisses > 0 }
            .map { key, fb in
                NudgeRow(id: key, title: title(forDedupeKey: key), source: source(forDedupeKey: key),
                         tally: "Accepted \(fb.accepts) · Dismissed \(fb.dismisses)",
                         verdict: verdict(for: fb, now: now), lastDismiss: fb.lastDismiss)
            }
            .sorted { lhs, rhs in
                switch (lhs.lastDismiss, rhs.lastDismiss) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return lhs.id < rhs.id
                }
            }
    }

    static func verdict(for fb: SuggestionFeedback, now: Date) -> NudgeVerdict {
        if fb.consecutiveDismisses >= ProactiveStore.suppressionThreshold,
           let last = fb.lastDismiss, now.timeIntervalSince(last) < ProactiveStore.decay {
            return .backedOff
        }
        if fb.accepts > 0 && fb.dismisses == 0 { return .welcomed }
        if fb.accepts == 0 && fb.dismisses > 0 { return .backedOff }
        return .mixed
    }

    static func source(forDedupeKey key: String) -> SuggestionSource? {
        switch key.prefix(while: { $0 != ":" && $0 != "." }) {
        case "routine":   return .routine
        case "calendar":  return .calendar
        case "command":   return .command
        case "screen":    return .screen
        case "downloads": return .downloads
        case "session":   return .session
        default:          return nil
        }
    }

    static func title(forDedupeKey key: String) -> String {
        switch source(forDedupeKey: key) {
        case .routine:   return "Routine suggestion"
        case .calendar:  return "Meeting reminder"
        case .command:   return "Command suggestion"
        case .screen:    return "On-screen help"
        case .downloads: return "New download"
        case .session:   return "Session recap"
        case nil:        return "Proactive nudge"
        }
    }
}

@MainActor
struct InsightsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var routines: [InsightsModel.LearnedRoutineRow] = []
    @State private var nudges: [InsightsModel.NudgeRow] = []
    @State private var observationDays = 0

    private var accent: Color { settings.accentColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "What Aria's learned",
                           subtitle: "Routines she's noticed and the nudges she's offered.")
                privacyNote
                routinesSection
                nudgesSection
                Spacer(minLength: 8)
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
    }

    private func load() async {
        let log = ObservationLog()
        let engine = PatternEngine(log: log)
        let patterns = await engine.allPatterns()
        let days = await log.observationDays(now: Date())
        let store = ProactiveStoreFile.load()
        routines = InsightsModel.learnedRoutineRows(from: patterns)
        nudges = InsightsModel.nudgeRows(from: store, now: Date())
        observationDays = days
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
            Text("All learning happens on this Mac. Nothing here is ever uploaded.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Learned routines", symbol: "repeat")
            if routines.isEmpty {
                AriaCard { AriaEmptyState(message: "Still learning your routines", detail: stillLearningMessage) }
            } else {
                VStack(spacing: 10) { ForEach(routines) { routineCard($0) } }
            }
        }
    }

    private var stillLearningMessage: String {
        let remaining = max(PatternEngine.observationGraceDays - observationDays, 0)
        if remaining > 0 {
            let days = remaining == 1 ? "a day" : "\(remaining) days"
            return "Give Aria \(days) more and she'll start recognising the things you do at the same time each day."
        }
        return "Nothing confident enough to show yet — keep using Aria and patterns will appear here."
    }

    private func routineCard(_ row: InsightsModel.LearnedRoutineRow) -> some View {
        AriaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.summary).font(.system(size: 14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    chip(row.statusLabel, color: accent)
                }
                confidenceMeter(row.confidence, label: row.confidenceLabel)
            }
        }
    }

    private func confidenceMeter(_ confidence: Double, label: String) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(accent)
                        .frame(width: max(6, geo.size.width * min(max(confidence, 0), 1)))
                }
            }
            .frame(height: 6)
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var nudgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recent nudges", symbol: "bell.badge")
            if nudges.isEmpty {
                AriaCard { AriaEmptyState(message: "No nudges yet",
                                          detail: "When Aria offers something proactively, you'll see it here — and whether you took her up on it.") }
            } else {
                VStack(spacing: 10) { ForEach(nudges) { nudgeCard($0) } }
            }
        }
    }

    private func nudgeCard(_ row: InsightsModel.NudgeRow) -> some View {
        AriaCard {
            HStack(spacing: 12) {
                Image(systemName: nudgeSymbol(row.source)).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accent).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).font(.system(size: 14, weight: .medium))
                    Text(row.tally).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                verdictChip(row.verdict)
            }
        }
    }

    private func verdictChip(_ verdict: InsightsModel.NudgeVerdict) -> some View {
        let (text, color): (String, Color) = {
            switch verdict {
            case .welcomed:  return ("Welcomed", .green)
            case .mixed:     return ("Mixed", .orange)
            case .backedOff: return ("Backed off", .secondary)
            }
        }()
        return chip(text, color: color)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func nudgeSymbol(_ source: SuggestionSource?) -> String {
        switch source {
        case .routine:   return "repeat"
        case .calendar:  return "calendar"
        case .command:   return "terminal"
        case .screen:    return "rectangle.on.rectangle"
        case .downloads: return "arrow.down.circle"
        case .session:   return "clock.arrow.circlepath"
        case nil:        return "sparkle"
        }
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 16, weight: .semibold, design: .rounded))
        }
    }
}
