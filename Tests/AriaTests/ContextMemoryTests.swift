import XCTest
@testable import Aria

private struct StubContextContributor: ContextContributor {
    let apps: [String]
    let activity: String?
    func contribute(to snapshot: inout Domain.ContextSnapshot) async {
        snapshot.apps.append(contentsOf: apps)
        if let activity { snapshot.activity = activity }
    }
}

final class ContextMemoryTests: XCTestCase {

    // MARK: - MemoryStore

    func testStoreAndRetrieveMemory() async {
        let bus = EventBus()
        let store = MemoryStore(eventBus: bus)
        let memory = Domain.Memory(scope: .longTerm, content: "fact", source: "test")
        await store.store(memory)

        let got = await store.get(memory.id)
        XCTAssertEqual(got?.content, "fact")

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.memoryStored))
    }

    func testAllFiltersByScope() async {
        let store = MemoryStore(eventBus: EventBus())
        await store.store(Domain.Memory(scope: .session, content: "s", source: "t"))
        await store.store(Domain.Memory(scope: .longTerm, content: "l", source: "t"))

        let longTerm = await store.all(scope: .longTerm)
        XCTAssertEqual(longTerm.map(\.content), ["l"])
    }

    func testPruneExpiredRemovesOnlyExpired() async {
        let store = MemoryStore(eventBus: EventBus())
        await store.store(Domain.Memory(scope: .session, content: "live", source: "t"))
        await store.store(Domain.Memory(scope: .session, content: "dead", source: "t",
                                        expiration: Date(timeIntervalSince1970: 100)))

        let removed = await store.pruneExpired(asOf: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(removed, 1)
        let remaining = await store.all()
        XCTAssertEqual(remaining.map(\.content), ["live"])
    }

    // MARK: - ContextCollector

    func testCollectorMergesSourcesAndEmits() async {
        let bus = EventBus()
        let collector = ContextCollector(eventBus: bus)
        await collector.addSource(StubContextContributor(apps: ["Mail"], activity: "writing"))
        await collector.addSource(StubContextContributor(apps: ["Safari"], activity: nil))

        let snapshot = await collector.snapshot()
        XCTAssertEqual(Set(snapshot.apps), ["Mail", "Safari"])
        XCTAssertEqual(snapshot.activity, "writing")

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.contextChanged))
    }

    // MARK: - Verifier

    func testVerifierPassesArtifactRule() {
        let report = ExecutionReport(completed: [UUID()], failed: [],
                                     artifacts: [Domain.Artifact(kind: .other, reference: "x")])
        let outcome = Verifier().verify(report: report, rules: ["artifact:other"])
        XCTAssertTrue(outcome.passed)
    }

    func testVerifierFailsMissingArtifactRule() {
        let report = ExecutionReport(completed: [UUID()], failed: [], artifacts: [])
        let outcome = Verifier().verify(report: report, rules: ["artifact:email"])
        XCTAssertFalse(outcome.passed)
        XCTAssertEqual(outcome.failedRules, ["artifact:email"])
    }

    func testVerifierMinCompletedRule() {
        let report = ExecutionReport(completed: [UUID()], failed: [], artifacts: [])
        XCTAssertFalse(Verifier().verify(report: report, rules: ["minCompleted:2"]).passed)
        XCTAssertTrue(Verifier().verify(report: report, rules: ["minCompleted:1"]).passed)
    }
}
