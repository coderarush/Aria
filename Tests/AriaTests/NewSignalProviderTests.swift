import XCTest
@testable import Aria

/// V11 P13 — two new proactive signal providers plugged into the existing
/// ProactiveEngine: a fresh PDF in Downloads offers a summary; a long work
/// session offers a recap. Providers are pure over injected inputs.
final class NewSignalProviderTests: XCTestCase {

    private func date(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 11
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // MARK: Downloads

    func testFreshPDFProducesSuggestion() async {
        let now = date(hour: 14)
        let provider = DownloadsSignalProvider(recentFiles: { _ in
            [DownloadsSignalProvider.NewFile(name: "Q3-report.pdf",
                                             addedAt: now.addingTimeInterval(-120))]
        })
        let suggestions = await provider.candidates(now: now)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.source, .downloads)
        XCTAssertTrue(suggestions.first?.spokenLine.contains("Q3-report") ?? false)
        if case .runCommand(let cmd) = suggestions.first!.action {
            XCTAssertTrue(cmd.lowercased().contains("summarize"))
            XCTAssertTrue(cmd.contains("Q3-report.pdf"))
        } else {
            XCTFail("expected runCommand")
        }
    }

    func testStaleOrNonPDFFilesIgnored() async {
        let now = date(hour: 14)
        let provider = DownloadsSignalProvider(recentFiles: { _ in
            [DownloadsSignalProvider.NewFile(name: "old.pdf", addedAt: now.addingTimeInterval(-3600)),
             DownloadsSignalProvider.NewFile(name: "movie.mp4", addedAt: now.addingTimeInterval(-60))]
        })
        let suggestions = await provider.candidates(now: now)
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testDedupeKeyStablePerFile() async {
        let now = date(hour: 14)
        let provider = DownloadsSignalProvider(recentFiles: { _ in
            [DownloadsSignalProvider.NewFile(name: "a.pdf", addedAt: now.addingTimeInterval(-60))]
        })
        let s1 = await provider.candidates(now: now)
        let s2 = await provider.candidates(now: now)
        XCTAssertEqual(s1.first?.dedupeKey, s2.first?.dedupeKey)
    }

    // MARK: Session recap

    func testBusySessionOffersRecap() async {
        let now = date(hour: 17)
        let provider = SessionSignalProvider(completedTasks: { _ in 5 })
        let suggestions = await provider.candidates(now: now)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.source, .session)
        if case .runCommand(let cmd) = suggestions.first!.action {
            XCTAssertTrue(cmd.lowercased().contains("today"))
        } else {
            XCTFail("expected runCommand")
        }
    }

    func testQuietSessionStaysQuiet() async {
        let provider = SessionSignalProvider(completedTasks: { _ in 2 })
        let suggestions = await provider.candidates(now: date(hour: 17))
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testRecapDedupesPerDay() async {
        let provider = SessionSignalProvider(completedTasks: { _ in 8 })
        let morning = await provider.candidates(now: date(hour: 11))
        let evening = await provider.candidates(now: date(hour: 18))
        XCTAssertEqual(morning.first?.dedupeKey, evening.first?.dedupeKey,
                       "one recap offer per day — engine suppression handles the rest")
    }

    // MARK: settings integration

    func testNewSourcesHaveDefaults() {
        let defaults = UserDefaults(suiteName: "nsp-\(UUID().uuidString)")!
        let s = ProactiveSettings.load(defaults)
        XCTAssertTrue(s.isSourceEnabled(.downloads))
        XCTAssertTrue(s.isSourceEnabled(.session))
    }
}
