import SwiftUI
import EventKit

/// The 60-second "wow" — the first thing a new user sees Aria *do*, before they
/// configure anything. Aria composes a live "Here's your day" card from whatever
/// is already available on the Mac (today's calendar, if it's already authorized,
/// plus the 2-3 most recently touched files in Downloads/Desktop) and presents it
/// under a breathing hero blob. It never prompts for permission, never blanks, and
/// never crashes: when calendar isn't granted it still shows recent files and a
/// tasteful nudge.
///
/// REUSE: the blob is `BlobShape` + `BlobMath` (the brand creature), not a redraw.
/// Pure presentation logic lives in `DayCard` so it can be unit-tested with injected
/// data — no EventKit, no filesystem in the tests.

// MARK: - Pure model + formatter (unit-tested)

/// A read-only snapshot the view renders. Built purely from injected data so the
/// "here's your day" formatting is fully testable without permissions or I/O.
struct DayCard: Equatable {

    /// One calendar event, already reduced to display strings.
    struct Event: Equatable {
        let time: String   // "10:00 AM"
        let title: String
    }

    /// One recent file, already reduced to display strings.
    struct FileItem: Equatable {
        let name: String   // "Q3-deck.pdf"
        let where_: String // "Downloads" / "Desktop"
    }

    /// Friendly date header, e.g. "Friday, June 13".
    let dateHeadline: String
    let greeting: String
    let events: [Event]
    let files: [FileItem]
    /// True when calendar access wasn't granted — drives the tasteful nudge.
    let calendarNudge: Bool

    var hasEvents: Bool { !events.isEmpty }
    var hasFiles: Bool { !files.isEmpty }

    /// A short spoken-style summary line ("You have 2 events today and 3 recent
    /// files.") — also what an optional TTS pass would read. Pure + deterministic.
    var summaryLine: String {
        var parts: [String] = []
        if hasEvents {
            parts.append(events.count == 1 ? "1 event today" : "\(events.count) events today")
        } else if !calendarNudge {
            parts.append("a clear calendar")
        }
        if hasFiles {
            parts.append(files.count == 1 ? "1 recent file" : "\(files.count) recent files")
        }
        if parts.isEmpty { return "Here's a look at your day." }
        let joined: String
        switch parts.count {
        case 1: joined = parts[0]
        case 2: joined = "\(parts[0]) and \(parts[1])"
        default: joined = parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        }
        return "You have \(joined)."
    }

    // MARK: Pure builders (the tested surface)

    /// Build the display card from already-extracted, injected data. This is the
    /// pure seam: the live view extracts events/files with EventKit + FileManager,
    /// then hands the raw values here. No I/O, no permissions, deterministic.
    static func make(now: Date,
                     calendarAuthorized: Bool,
                     rawEvents: [(start: Date, title: String, allDay: Bool)],
                     rawFiles: [(name: String, location: String)],
                     calendar: Calendar = .current) -> DayCard {
        let dateFmt = DateFormatter()
        dateFmt.calendar = calendar
        dateFmt.locale = .current
        dateFmt.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let headline = dateFmt.string(from: now)

        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.locale = .current
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none

        let events: [Event] = rawEvents
            .filter { !$0.allDay }
            .sorted { $0.start < $1.start }
            .prefix(4)
            .map { Event(time: timeFmt.string(from: $0.start),
                         title: cleanTitle($0.title)) }

        let files: [FileItem] = rawFiles
            .prefix(3)
            .map { FileItem(name: $0.name, where_: $0.location) }

        return DayCard(dateHeadline: headline,
                       greeting: greeting(for: now, calendar: calendar),
                       events: events,
                       files: files,
                       calendarNudge: !calendarAuthorized)
    }

    /// Time-of-day greeting — purely a function of the clock.
    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: date)
        switch h {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default:      return "Hello."
        }
    }

    /// Trim and de-blank a title so the card never shows an empty or whitespace row.
    static func cleanTitle(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled event" : t
    }
}

// MARK: - Live data gathering (graceful, prompt-free)

/// Reads real data only when it's already permitted, exactly like BriefingComposer
/// (no involuntary EventKit prompt). Everything degrades to empty on any failure.
@MainActor
enum MeetAriaData {

    /// True only when full calendar access is already granted. Mirrors the
    /// prompt-free guard used across the app.
    static var calendarAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Today's timed events — read only when already authorized, never prompting.
    static func todaysEvents(now: Date = Date()) -> [(start: Date, title: String, allDay: Bool)] {
        guard calendarAuthorized else { return [] }
        let store = EKEventStore()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map { (start: $0.startDate ?? start, title: $0.title ?? "", allDay: $0.isAllDay) }
    }

    /// The 2-3 most-recently-touched files across Downloads and Desktop, newest
    /// first. Replicates the FileManager read pattern used by the proactive
    /// signal providers — content-modification date, hidden files skipped, no
    /// imports of private internals. Any failure → empty.
    static func recentFiles(limit: Int = 3) -> [(name: String, location: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders: [(url: URL, label: String)] = [
            (home.appendingPathComponent("Downloads"), "Downloads"),
            (home.appendingPathComponent("Desktop"), "Desktop")
        ]
        var scored: [(name: String, location: String, when: Date)] = []
        for folder in folders {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: folder.url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if vals?.isDirectory == true { continue }
                guard let when = vals?.contentModificationDate else { continue }
                scored.append((name: url.lastPathComponent, location: folder.label, when: when))
            }
        }
        return scored
            .sorted { $0.when > $1.when }
            .prefix(limit)
            .map { (name: $0.name, location: $0.location) }
    }

    /// Compose the live card from real (already-permitted) sources.
    static func liveCard(now: Date = Date()) -> DayCard {
        DayCard.make(now: now,
                     calendarAuthorized: calendarAuthorized,
                     rawEvents: todaysEvents(now: now),
                     rawFiles: recentFiles())
    }
}

// MARK: - The step view

/// The "Meet Aria" onboarding step: breathing hero blob + a live "Here's your day"
/// card + an optional, clearly-labeled "Speak it" affordance (visual only — it does
/// not autoplay audio or touch the voice engine) + a "This is just the start" CTA.
@MainActor
struct MeetAriaStep: View {
    let accent: Color
    /// Called when the user taps the forward CTA.
    var onContinue: () -> Void
    /// Injectable for previews/tests; production reads the live, permitted card.
    var cardProvider: () -> DayCard = { MeetAriaData.liveCard() }

    @State private var card: DayCard?
    @State private var revealCard = false
    @State private var speakAcknowledged = false

    var body: some View {
        VStack(spacing: 18) {
            hero

            Group {
                if let card {
                    dayCard(card)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    composingPlaceholder
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: revealCard)

            continueButton
        }
        .frame(maxWidth: 460)
        .onAppear {
            // Compose the live card once, then reveal with a beat so the moment
            // reads as Aria *doing* something rather than a static screen.
            guard card == nil else { return }
            let built = cardProvider()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation { card = built; revealCard = true }
            }
        }
    }

    // MARK: Hero (the breathing brand blob)

    private var hero: some View {
        VStack(spacing: 10) {
            HeroBlob(accent: accent)
                .frame(width: 96, height: 96)
            Text("Meet Aria")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Let me show you what I can do.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var composingPlaceholder: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Composing your day\u{2026}")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }

    // MARK: The live "Here's your day" card

    private func dayCard(_ card: DayCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: greeting + date + optional "Speak it".
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.greeting)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(card.dateHeadline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                speakButton(card)
            }

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    eventsSection(card)
                    filesSection(card)
                    if !card.hasEvents && !card.hasFiles {
                        Text("Nothing on the calendar and no recent files \u{2014} a clean slate. Ask me anything once we're set up.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 150)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.18), radius: 18, y: 8)
    }

    @ViewBuilder
    private func eventsSection(_ card: DayCard) -> some View {
        if card.hasEvents {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("TODAY", "calendar")
                ForEach(Array(card.events.enumerated()), id: \.offset) { _, ev in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ev.time)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                            .frame(width: 76, alignment: .leading)
                        Text(ev.title)
                            .font(.callout)
                            .lineLimit(1)
                    }
                }
            }
        } else if card.calendarNudge {
            // No calendar access — a tasteful nudge, never a blank.
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(accent)
                Text("Grant calendar access to see your schedule here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func filesSection(_ card: DayCard) -> some View {
        if card.hasFiles {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("RECENT FILES", "doc.text")
                ForEach(Array(card.files.enumerated()), id: \.offset) { _, f in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: f.name))
                            .font(.system(size: 13))
                            .foregroundStyle(accent)
                            .frame(width: 18)
                        Text(f.name)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(f.where_)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.5)
        }
        .foregroundStyle(.secondary)
    }

    /// Optional, clearly-labeled affordance. By design it does NOT autoplay audio
    /// or wire the voice engine — the visual wow is the moment; this just confirms
    /// what Aria *would* say, so the promise lands without any audio risk.
    private func speakButton(_ card: DayCard) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                speakAcknowledged = true
            }
        } label: {
            Label(speakAcknowledged ? "Aria will speak this" : "Speak it",
                  systemImage: speakAcknowledged ? "checkmark.circle.fill" : "speaker.wave.2.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(accent)
        .help(card.summaryLine)
    }

    private var continueButton: some View {
        Button {
            onContinue()
        } label: {
            Text("This is just the start \u{2192}")
                .fontWeight(.semibold)
                .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .controlSize(.large)
    }

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "tiff": return "photo"
        case "mov", "mp4", "m4v": return "film"
        case "zip", "dmg", "pkg": return "shippingbox"
        case "key", "ppt", "pptx": return "rectangle.on.rectangle"
        case "doc", "docx", "pages", "txt", "md", "rtf": return "doc.text"
        case "xls", "xlsx", "csv", "numbers": return "tablecells"
        default: return "doc"
        }
    }
}

// MARK: - Hero blob (reuses BlobShape / BlobMath)

/// A calm, breathing instance of the brand creature for the onboarding hero.
/// Reuses `BlobShape` + `BlobMath` verbatim — no new blob math, no IslandView
/// dependency — so the moment shows the *real* Aria, gently alive.
@MainActor
private struct HeroBlob: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // Slow, calm breathing — a touch of wobble so it reads as living.
            let breathe = 0.5 + 0.5 * sin(t * 1.4)
            let amp = 0.08 + breathe * 0.04
            let radii = BlobMath.radii(t: t, n: 11, amp: amp, speed: 1.0)
            let c1 = accent
            let c0 = accent.opacity(0.78)
            BlobShape(radii: radii)
                .fill(LinearGradient(colors: [c0, c1],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    BlobShape(radii: radii)
                        .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                             center: .init(x: 0.38, y: 0.30),
                                             startRadius: 1, endRadius: 40))
                )
                .scaleEffect(1 + breathe * 0.05)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
                .shadow(color: accent.opacity(0.30 + 0.18 * breathe), radius: 16)
        }
    }
}
