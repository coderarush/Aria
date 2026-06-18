import XCTest
@testable import Aria

final class MemoryGraphToolTests: XCTestCase {

    private func make() -> (GoalEngine, SessionMemoryStore, WorkJournal, ActivityLog, MemoryGraph) {
        func url(_ t: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("aria-mgt-\(t)-\(UUID().uuidString).json")
        }
        let wj = WorkJournal(fileURL: url("wj")); let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g")); let sm = SessionMemoryStore(fileURL: url("sm"))
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al), activity: al,
                                goals: g, sessions: sm, context: ContextCoordinator())
        return (g, sm, wj, al, MemoryGraph(goals: g, sessions: sm, timeline: tl))
    }
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    func testRelatedWork() async throws {
        let (g, sm, _, _, mg) = make()
        _ = await g.create(title: "Ship V12", project: "Aria", now: t)
        await sm.record(SessionSnapshot(project: "Aria", goal: "Ship V12", date: t))
        let tool = MemoryGraphTool(graph: mg, goals: g, now: { [t] in t.addingTimeInterval(10) })
        let r = try await tool.run(input: ["action": "related", "subject": "ship"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("Aria"))   // related project surfaces
    }

    func testWhyExplainsWithReason() async throws {
        let (g, _, _, _, mg) = make()
        _ = await g.create(title: "Ship V12", project: "Aria", now: t)
        let tool = MemoryGraphTool(graph: mg, goals: g, now: { [t] in t.addingTimeInterval(10) })
        let r = try await tool.run(input: ["action": "why", "subject": "ship"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.lowercased().contains("project") || r.output.contains("Aria"))
    }

    func testChangedListsEvents() async throws {
        let (g, _, wj, _, mg) = make()
        _ = await g.create(title: "Ship V12", project: "Aria", now: t)
        await wj.record(kind: .task, title: "fixed tests", outcome: "", ok: true,
                        project: "Aria", at: t)
        let tool = MemoryGraphTool(graph: mg, goals: g, now: { [t] in t.addingTimeInterval(10) })
        let r = try await tool.run(input: ["action": "changed", "subject": "ship"])
        XCTAssertTrue(r.success)
    }

    func testUnknownGoalFails() async throws {
        let (g, _, _, _, mg) = make()
        let tool = MemoryGraphTool(graph: mg, goals: g, now: { [t] in t })
        let r = try await tool.run(input: ["action": "related", "subject": "nope"])
        XCTAssertFalse(r.success)
    }

    func testUnknownActionFails() async throws {
        let (g, _, _, _, mg) = make()
        _ = await g.create(title: "G", project: nil, now: t)
        let tool = MemoryGraphTool(graph: mg, goals: g, now: { [t] in t })
        let r = try await tool.run(input: ["action": "frob", "subject": "g"])
        XCTAssertFalse(r.success)
    }
}
