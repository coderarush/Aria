import XCTest
@testable import Aria

final class MemoryGraphTests: XCTestCase {

    private func makeStores() -> (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine) {
        func url(_ t: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("aria-mg-\(t)-\(UUID().uuidString).json")
        }
        let wj = WorkJournal(fileURL: url("wj"))
        let al = ActivityLog(url: url("al"))
        let g = GoalEngine(fileURL: url("g"))
        let sm = SessionMemoryStore(fileURL: url("sm"))
        let tl = TimelineEngine(timeline: Timeline(journal: wj, activity: al),
                                activity: al, goals: g, sessions: sm, context: ContextCoordinator())
        return (wj, al, g, sm, tl)
    }
    private func graph(_ s: (WorkJournal, ActivityLog, GoalEngine, SessionMemoryStore, TimelineEngine),
                       fanoutCap: Int = 12) -> MemoryGraph {
        MemoryGraph(goals: s.2, sessions: s.3, timeline: s.4, fanoutCap: fanoutCap)
    }
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: explicit links

    func testLinkAndNeighbors() async {
        let s = makeStores(); let mg = graph(s)
        let decision = GraphNode.decision(id: "d1", label: "use derive-on-read")
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        await mg.link(decision, GraphNode.goal(g), relation: .motivates,
                      reason: "design call", confidence: 0.8)
        let ns = await mg.neighbors(of: decision, now: t.addingTimeInterval(10))
        XCTAssertEqual(ns.map(\.to.label), ["Ship V12"])
        XCTAssertEqual(ns.first?.relation, .motivates)
        XCTAssertEqual(ns.first?.confidence, 0.8)
        XCTAssertFalse(ns.first?.reason.isEmpty ?? true)
        XCTAssertFalse(ns.first?.source.isEmpty ?? true)
    }

    func testDuplicateEdgesDeduped() async {
        let s = makeStores(); let mg = graph(s)
        let a = GraphNode.decision(id: "d", label: "d")
        let g = await s.2.create(title: "G", project: nil, now: t)!
        let gn = GraphNode.goal(g)
        await mg.link(a, gn, relation: .motivates, reason: "x", confidence: 0.5)
        await mg.link(a, gn, relation: .motivates, reason: "x", confidence: 0.9)
        let ns = await mg.neighbors(of: a, now: t)
        XCTAssertEqual(ns.count, 1)
        XCTAssertEqual(ns.first?.confidence, 0.9)   // keeps the strongest
    }

    // MARK: derived edges (no storage — read from existing stores)

    func testGoalProjectDerivedEdge() async {
        let s = makeStores(); let mg = graph(s)
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        let ns = await mg.neighbors(of: GraphNode.goal(g), now: t.addingTimeInterval(10))
        let proj = ns.first { $0.to.kind == .project }
        XCTAssertEqual(proj?.to.label, "Aria")
        XCTAssertEqual(proj?.relation, .inProject)
        XCTAssertEqual(proj?.confidence, 1.0)
        XCTAssertTrue(proj?.source.contains("project") ?? false)
    }

    func testGoalSessionDerivedByTitleMatch() async {
        let s = makeStores(); let mg = graph(s)
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        await s.3.record(SessionSnapshot(project: "Aria", goal: "Ship V12",
                                         progress: "wip", date: t))
        let ns = await mg.neighbors(of: GraphNode.goal(g), now: t.addingTimeInterval(10))
        let sess = ns.first { $0.to.kind == .session }
        XCTAssertNotNil(sess)
        XCTAssertEqual(sess?.relation, .hasSession)
        XCTAssertGreaterThanOrEqual(sess?.confidence ?? 0, 0.85)   // exact title match
    }

    func testProjectToSessionsAndGoals() async {
        let s = makeStores(); let mg = graph(s)
        _ = await s.2.create(title: "G", project: "Aria", now: t)
        await s.3.record(SessionSnapshot(project: "Aria", goal: "session work", date: t))
        let ns = await mg.neighbors(of: GraphNode.project("Aria"), now: t.addingTimeInterval(10))
        XCTAssertTrue(ns.contains { $0.to.kind == .session })
        XCTAssertTrue(ns.contains { $0.to.kind == .goal })
    }

    func testSessionToTimelineEvent() async {
        let s = makeStores(); let mg = graph(s)
        await s.0.record(kind: .task, title: "ran suite", outcome: "ok", ok: true,
                         project: "Aria", at: t)
        await s.3.record(SessionSnapshot(project: "Aria", goal: "work", date: t))
        let snap = await s.3.latest(now: t.addingTimeInterval(5))!
        let ns = await mg.neighbors(of: GraphNode.session(snap), now: t.addingTimeInterval(10))
        XCTAssertTrue(ns.contains { $0.to.kind == .timelineEvent })
    }

    // MARK: traversal

    func testRelatedWithinDepth() async {
        let s = makeStores(); let mg = graph(s)
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        await s.3.record(SessionSnapshot(project: "Aria", goal: "Ship V12", date: t))
        await s.0.record(kind: .task, title: "did thing", outcome: "", ok: true,
                         project: "Aria", at: t)
        let nodes = await mg.related(to: GraphNode.goal(g), depth: 2, now: t.addingTimeInterval(10))
        XCTAssertTrue(nodes.contains { $0.kind == .project && $0.label == "Aria" })
        XCTAssertTrue(nodes.contains { $0.kind == .session })
    }

    func testTraversalDepthHardCapThree() async {
        let s = makeStores(); let mg = graph(s)
        let g = await s.2.create(title: "G", project: "Aria", now: t)!
        // depth 99 must clamp to <= 3 hops; call must terminate and stay bounded.
        let nodes = await mg.related(to: GraphNode.goal(g), depth: 99, now: t.addingTimeInterval(10))
        XCTAssertLessThan(nodes.count, 500)   // bounded, no explosion
    }

    func testCyclesTerminate() async {
        let s = makeStores(); let mg = graph(s)
        let a = GraphNode.decision(id: "a", label: "a")
        let b = GraphNode.decision(id: "b", label: "b")
        await mg.link(a, b, relation: .relatedTo, reason: "x", confidence: 0.5)
        await mg.link(b, a, relation: .relatedTo, reason: "x", confidence: 0.5)
        let nodes = await mg.related(to: a, depth: 3, now: t)   // must not loop forever
        XCTAssertTrue(nodes.contains { $0.label == "b" })
    }

    func testMissingNodeReturnsEmpty() async {
        let s = makeStores(); let mg = graph(s)
        let ghost = GraphNode.goal(Goal(id: "does-not-exist", title: "ghost"))
        let ns = await mg.neighbors(of: ghost, now: t)
        XCTAssertTrue(ns.isEmpty)
    }

    // MARK: explainability

    func testExplainReturnsSourceReasonConfidence() async {
        let s = makeStores(); let mg = graph(s)
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        let edge = await mg.explain(GraphNode.goal(g), GraphNode.project("Aria"),
                                    now: t.addingTimeInterval(10))
        XCTAssertNotNil(edge)
        XCTAssertFalse(edge?.source.isEmpty ?? true)
        XCTAssertFalse(edge?.reason.isEmpty ?? true)
        XCTAssertEqual(edge?.confidence, 1.0)
    }

    func testTraceLedToThis() async {
        let s = makeStores(); let mg = graph(s)
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        let decision = GraphNode.decision(id: "d1", label: "ship decision")
        await mg.link(decision, GraphNode.goal(g), relation: .motivates,
                      reason: "founder call", confidence: 0.9)
        let edges = await mg.trace(from: GraphNode.goal(g), depth: 3, now: t.addingTimeInterval(10))
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.allSatisfy { !$0.reason.isEmpty && !$0.source.isEmpty })
    }

    func testConfidenceFilter() async {
        let s = makeStores(); let mg = graph(s)
        let a = GraphNode.decision(id: "a", label: "a")
        let weak = GraphNode.decision(id: "w", label: "weak")
        let strong = GraphNode.decision(id: "s", label: "strong")
        await mg.link(a, weak, relation: .relatedTo, reason: "x", confidence: 0.2)
        await mg.link(a, strong, relation: .relatedTo, reason: "x", confidence: 0.9)
        let ns = await mg.neighbors(of: a, minConfidence: 0.5, now: t)
        XCTAssertEqual(ns.map(\.to.label), ["strong"])
    }

    // MARK: bounded + deterministic

    func testFanoutCapped() async {
        let s = makeStores(); let mg = graph(s, fanoutCap: 5)
        for i in 0..<20 {
            await s.3.record(SessionSnapshot(project: "Aria", goal: "s\(i)",
                                             date: t.addingTimeInterval(Double(i))))
        }
        let ns = await mg.neighbors(of: GraphNode.project("Aria"), now: t.addingTimeInterval(100))
        XCTAssertLessThanOrEqual(ns.count, 5)
    }

    func testDeterministicOrder() async {
        let s = makeStores(); let mg = graph(s)
        let a = GraphNode.decision(id: "a", label: "a")
        await mg.link(a, GraphNode.decision(id: "lo", label: "lo"), relation: .relatedTo, reason: "x", confidence: 0.3)
        await mg.link(a, GraphNode.decision(id: "hi", label: "hi"), relation: .relatedTo, reason: "x", confidence: 0.9)
        let first = await mg.neighbors(of: a, now: t)
        let second = await mg.neighbors(of: a, now: t)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.to.label), ["hi", "lo"])   // confidence-desc, stable
    }

    // MARK: retention + cross-session

    func testRetentionInteraction() async {
        let s = makeStores(); let mg = graph(s)
        let now = t
        // A snapshot 20 days old with 14-day ttl is expired — must not appear.
        await s.3.record(SessionSnapshot(project: "Aria", goal: "old",
                                         date: now.addingTimeInterval(-20 * 86400), ttlDays: 14),
                         now: now)
        _ = await s.2.create(title: "Ship V12", project: "Aria", now: now)
        let ns = await mg.neighbors(of: GraphNode.project("Aria"), now: now)
        XCTAssertFalse(ns.contains { $0.to.kind == .session && $0.to.label.contains("old") })
    }

    func testCrossSessionResume() async {
        let s = makeStores()
        let g = await s.2.create(title: "Ship V12", project: "Aria", now: t)!
        await s.3.record(SessionSnapshot(project: "Aria", goal: "Ship V12", date: t))
        // Fresh graph instance over the SAME durable stores — relationships rebuild.
        let mg2 = MemoryGraph(goals: s.2, sessions: s.3, timeline: s.4)
        let ns = await mg2.neighbors(of: GraphNode.goal(g), now: t.addingTimeInterval(10))
        XCTAssertTrue(ns.contains { $0.to.kind == .session })
    }
}
