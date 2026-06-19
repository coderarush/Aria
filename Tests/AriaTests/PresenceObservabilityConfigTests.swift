import XCTest
@testable import Aria

private struct MeetingRule: PresenceRule {
    func evaluate(_ snapshot: Domain.ContextSnapshot) -> PresenceOpportunity? {
        guard snapshot.activity == "meeting" else { return nil }
        return PresenceOpportunity(title: "Prep your meeting",
                                   reason: "you're in a meeting",
                                   priority: .high)
    }
}

final class PresenceObservabilityConfigTests: XCTestCase {

    // MARK: - FeatureFlags (spec §19)

    func testFlagsDefaultToFalse() {
        XCTAssertFalse(FeatureFlags().isEnabled("speculative-exec"))
    }

    func testFlagsRespectDefaultsAndOverrides() {
        var flags = FeatureFlags(defaults: ["a": true])
        XCTAssertTrue(flags.isEnabled("a"))
        flags.set("b", true)
        XCTAssertTrue(flags.isEnabled("b"))
        flags.set("a", false)
        XCTAssertFalse(flags.isEnabled("a"))
    }

    func testFlagsDefaultEnvironmentIsHybrid() {
        XCTAssertEqual(FeatureFlags().environment, .hybrid)
    }

    // MARK: - KeyValueStore (spec §18 storage seam)

    func testInMemoryStoreRoundTrips() async {
        let store = InMemoryKeyValueStore()
        await store.set("v", forKey: "k")
        let got = await store.string(forKey: "k")
        XCTAssertEqual(got, "v")
        await store.remove(forKey: "k")
        let gone = await store.string(forKey: "k")
        XCTAssertNil(gone)
    }

    // MARK: - MetricsCollector (spec §22)

    func testMetricsTallyByKind() async {
        let metrics = MetricsCollector()
        await metrics.ingest([
            AriaEvent(kind: .taskStarted, source: "a"),
            AriaEvent(kind: .taskStarted, source: "b"),
            AriaEvent(kind: .toolExecuted, source: "c"),
        ])
        let started = await metrics.count(of: .taskStarted)
        let total = await metrics.total()
        XCTAssertEqual(started, 2)
        XCTAssertEqual(total, 3)
    }

    // MARK: - ExecutionTimeline (spec §22)

    func testTimelineRecordsRecentInOrder() async {
        let timeline = ExecutionTimeline()
        await timeline.ingest([
            AriaEvent(kind: .appOpened, source: "1"),
            AriaEvent(kind: .windowFocused, source: "2"),
            AriaEvent(kind: .contextChanged, source: "3"),
        ])
        let recent = await timeline.recent(2)
        XCTAssertEqual(recent.map(\.source), ["2", "3"])
    }

    // MARK: - PresenceDetector (spec §presence)

    func testDetectorFiresMatchingRuleAndEmits() async {
        let bus = EventBus()
        let detector = PresenceDetector(eventBus: bus)
        await detector.addRule(MeetingRule())

        let hits = await detector.detect(in: Domain.ContextSnapshot(activity: "meeting"))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.priority, .high)

        let kinds = await bus.replay().map(\.kind)
        XCTAssertTrue(kinds.contains(.presenceOpportunity))
    }

    func testDetectorSilentWhenNoRuleMatches() async {
        let detector = PresenceDetector(eventBus: EventBus())
        await detector.addRule(MeetingRule())
        let hits = await detector.detect(in: Domain.ContextSnapshot(activity: "coding"))
        XCTAssertTrue(hits.isEmpty)
    }
}
