import XCTest
@testable import Aria

final class BriefingTests: XCTestCase {

    func testIntentDetection() {
        for s in ["brief me", "Give me my daily briefing", "morning briefing please",
                  "what's my briefing", "Brief me for today"] {
            XCTAssertTrue(BriefingComposer.isBriefingIntent(s), s)
        }
        for s in ["briefly explain quantum physics", "be brief", "open briefcase folder"] {
            XCTAssertFalse(BriefingComposer.isBriefingIntent(s), s)
        }
    }

    func testPromptContainsAllSections() {
        let p = BriefingComposer.prompt(
            calendar: "• 10:00 Investor sync",
            reminders: "• Send deck",
            yesterdayWork: "✓ 14:00 research mics — note saved",
            recentDocs: "pricing-notes.md",
            date: Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertTrue(p.contains("Investor sync"))
        XCTAssertTrue(p.contains("Send deck"))
        XCTAssertTrue(p.contains("research mics"))
        XCTAssertTrue(p.contains("pricing-notes"))
        XCTAssertTrue(p.lowercased().contains("briefing"))
    }

    func testPromptHandlesEmptyInputsGracefully() {
        let p = BriefingComposer.prompt(calendar: "", reminders: "", yesterdayWork: "",
                                        recentDocs: "", date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(p.contains("(none)"), "empty sections must read as none, not vanish")
    }

    // V11 P4 — projects and notes feed the briefing.

    func testPromptIncludesProjectsAndNotes() {
        let p = BriefingComposer.prompt(
            calendar: "", reminders: "", yesterdayWork: "", recentDocs: "",
            projects: "• Verdai — last: ✓ deck",
            notes: "• Investor questions",
            date: Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertTrue(p.contains("Verdai"))
        XCTAssertTrue(p.contains("Investor questions"))
        XCTAssertTrue(p.contains("ACTIVE PROJECTS"))
        XCTAssertTrue(p.contains("RECENT NOTES"))
    }

    func testActiveProjectsDigestShowsLatestOutcome() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString).json")
        let j = WorkJournal(fileURL: url)
        await j.record(kind: .task, title: "deck", outcome: "6 slides", ok: true, project: "Verdai")
        let digest = await BriefingComposer.activeProjects(journal: j)
        XCTAssertTrue(digest.contains("Verdai"))
        XCTAssertTrue(digest.contains("deck"))
    }
}

final class KnowledgeRecentDocsTests: XCTestCase {
    func testRecentDocumentsNewestFirst() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("krd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "old".write(to: dir.appendingPathComponent("old.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        try "new".write(to: dir.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)

        let index = KnowledgeIndex(storeURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("krd-store-\(UUID().uuidString).json"))
        _ = await index.reindex(folders: [dir.path])
        let recent = await index.recentDocuments(limit: 2)
        XCTAssertEqual(recent.first?.title, "new")
    }
}
