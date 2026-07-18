import XCTest
@testable import Aria

final class Part4PerceptionTests: XCTestCase {

    private func obs(_ source: String, confidence: Double = 0.9,
                     tags: [String] = [], ts: TimeInterval = 1_000) -> Observation {
        Observation(source: source, confidence: confidence,
                    payload: ["k": "v"], tags: tags, timestamp: Date(timeIntervalSince1970: ts))
    }

    // MARK: - ObservationPolicy (§83)

    func testPolicyAdmitsByConfidence() {
        let policy = ObservationPolicy(minConfidence: 0.5, maxRetained: 100)
        XCTAssertTrue(policy.admits(obs("screen", confidence: 0.8)))
        XCTAssertFalse(policy.admits(obs("screen", confidence: 0.2)))
    }

    // MARK: - PerceptionStore (§70/§83)

    func testStoreBoundedRetentionEvictsOldest() async {
        let store = PerceptionStore(maxRetained: 2)
        await store.store(obs("a", ts: 1))
        await store.store(obs("b", ts: 2))
        await store.store(obs("c", ts: 3))
        let all = await store.all()
        XCTAssertEqual(all.map(\.source), ["b", "c"])
    }

    func testStoreFiltersBySourceAndDeletes() async {
        let store = PerceptionStore(maxRetained: 100)
        let screen = obs("screen")
        await store.store(screen)
        await store.store(obs("audio"))
        let screens = await store.all(source: "screen")
        XCTAssertEqual(screens.count, 1)

        await store.delete(screen.id)
        let afterDelete = await store.all(source: "screen")
        XCTAssertTrue(afterDelete.isEmpty)
    }

    // MARK: - PerceptionEngine (§69/§70) — observes, never executes

    func testIngestAdmitsAndPublishes() async {
        let bus = ObservationBus()
        let store = PerceptionStore(maxRetained: 100)
        let engine = PerceptionEngine(bus: bus, store: store,
                                      policy: ObservationPolicy(minConfidence: 0.5, maxRetained: 100))
        let admitted = await engine.ingest(obs("screen", confidence: 0.9))
        XCTAssertTrue(admitted)
        let stored = await store.all()
        XCTAssertEqual(stored.count, 1)
        let published = await bus.replay()
        XCTAssertEqual(published.count, 1)
    }

    func testIngestRejectsLowConfidence() async {
        let store = PerceptionStore(maxRetained: 100)
        let engine = PerceptionEngine(bus: ObservationBus(), store: store,
                                      policy: ObservationPolicy(minConfidence: 0.5, maxRetained: 100))
        let admitted = await engine.ingest(obs("screen", confidence: 0.1))
        XCTAssertFalse(admitted)
        let stored = await store.all()
        XCTAssertTrue(stored.isEmpty)
    }
}
