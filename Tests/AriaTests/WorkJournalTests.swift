import XCTest
@testable import Aria

final class WorkJournalTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString).json")
    }

    private func day(_ d: Int, hour: Int = 10) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = d; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    func testRecordsAndRecallsByDayRange() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "research USB mics", outcome: "Saved a note with 3 picks", ok: true, at: day(9))
        await j.record(kind: .agent, title: "Daily briefing", outcome: "Briefing saved", ok: true, at: day(10, hour: 9))
        await j.record(kind: .task, title: "organize downloads", outcome: "12 files sorted", ok: true, at: day(10, hour: 15))

        let yesterday = await j.entries(from: day(9, hour: 0), to: day(10, hour: 0))
        XCTAssertEqual(yesterday.map(\.title), ["research USB mics"])

        let today = await j.entries(from: day(10, hour: 0), to: day(11, hour: 0))
        XCTAssertEqual(today.count, 2)
    }

    func testSearchMatchesTitleAndOutcome() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "draft investor email", outcome: "Draft ready in Mail", ok: true, at: day(8))
        await j.record(kind: .task, title: "fix website", outcome: "pushed to github", ok: true, at: day(9))
        let hits = await j.search("investor", limit: 5)
        XCTAssertEqual(hits.map(\.title), ["draft investor email"])
        let outcomeHits = await j.search("github", limit: 5)
        XCTAssertEqual(outcomeHits.map(\.title), ["fix website"])
    }

    func testCapsAndPersists() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let j = WorkJournal(fileURL: url, cap: 5)
        for i in 0..<9 {
            await j.record(kind: .task, title: "t\(i)", outcome: "", ok: true, at: day(9).addingTimeInterval(Double(i)))
        }
        let j2 = WorkJournal(fileURL: url, cap: 5)
        let all = await j2.entries(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.last?.title, "t8")
    }

    func testSurvivesCorruptFile() async {
        let url = tempURL()
        try? Data("}{".utf8).write(to: url)
        let j = WorkJournal(fileURL: url)
        let all = await j.entries(from: .distantPast, to: .distantFuture)
        XCTAssertTrue(all.isEmpty)
    }

    func testDigestFormatsForBriefing() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "research mics", outcome: "note saved", ok: true, at: day(9))
        await j.record(kind: .task, title: "broken thing", outcome: "couldn't reach API", ok: false, at: day(9, hour: 12))
        let digest = await j.digest(from: day(9, hour: 0), to: day(10, hour: 0))
        XCTAssertTrue(digest.contains("research mics"))
        XCTAssertTrue(digest.contains("✗") || digest.lowercased().contains("fail"))
    }
}
