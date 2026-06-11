import XCTest
@testable import Aria

final class RecallWorkToolTests: XCTestCase {

    /// Fixed clock: NOON, so "1 hour ago" can never roll into yesterday when
    /// the suite runs near midnight (this exact flake happened live).
    private let fixedNow: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 10; c.hour = 12
        return Calendar.current.date(from: c)!
    }()

    private func journal() async -> WorkJournal {
        let j = WorkJournal(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("rwt-\(UUID().uuidString).json"))
        let cal = Calendar.current
        await j.record(kind: .task, title: "research USB mics", outcome: "note saved", ok: true,
                       at: cal.date(byAdding: .day, value: -1, to: fixedNow)!)
        await j.record(kind: .task, title: "draft investor email", outcome: "draft ready", ok: true,
                       at: fixedNow.addingTimeInterval(-3600))
        return j
    }

    func testYesterdayTimeframe() async throws {
        let tool = RecallWorkTool(journal: await journal(), now: { self.fixedNow })
        let r = try await tool.run(input: ["timeframe": "yesterday"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("USB mics"), r.output)
        XCTAssertFalse(r.output.contains("investor"), "today's work must not leak into yesterday")
    }

    func testTodayTimeframe() async throws {
        let tool = RecallWorkTool(journal: await journal(), now: { self.fixedNow })
        let r = try await tool.run(input: ["timeframe": "today"])
        XCTAssertTrue(r.output.contains("investor"), r.output)
    }

    func testFreeQuerySearch() async throws {
        let tool = RecallWorkTool(journal: await journal())
        let r = try await tool.run(input: ["query": "mics"])
        XCTAssertTrue(r.output.contains("USB mics"), r.output)
    }

    func testEmptyJournalIsHonest() async throws {
        let empty = WorkJournal(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("rwt-empty-\(UUID().uuidString).json"))
        let tool = RecallWorkTool(journal: empty)
        let r = try await tool.run(input: ["timeframe": "yesterday"])
        XCTAssertTrue(r.output.lowercased().contains("nothing"), r.output)
    }
}
