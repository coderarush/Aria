import XCTest
@testable import Aria

final class Part4FusionTests: XCTestCase {

    private func obs(_ source: String, confidence: Double, summary: String,
                     ts: TimeInterval) -> Observation {
        Observation(source: source, confidence: confidence,
                    payload: ["summary": summary], timestamp: Date(timeIntervalSince1970: ts))
    }

    // MARK: - ConflictResolver (§75)

    func testResolverRemovesStale() {
        let resolver = ConflictResolver()
        let old = obs("screen", confidence: 0.9, summary: "old", ts: 0)
        let fresh = obs("audio", confidence: 0.9, summary: "fresh", ts: 1_000)
        let resolved = resolver.resolve([old, fresh],
                                        now: Date(timeIntervalSince1970: 1_000),
                                        staleAfter: 100)
        XCTAssertEqual(resolved.map(\.source), ["audio"])
    }

    func testResolverDedupesKeepingNewest() {
        let resolver = ConflictResolver()
        let older = obs("screen", confidence: 0.9, summary: "same", ts: 100)
        let newer = obs("screen", confidence: 0.9, summary: "same", ts: 200)
        let resolved = resolver.resolve([older, newer],
                                        now: Date(timeIntervalSince1970: 200),
                                        staleAfter: 10_000)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.timestamp, Date(timeIntervalSince1970: 200))
    }

    // MARK: - FusionEngine (§75)

    func testFusePicksHighestConfidenceAsCurrent() async {
        let fusion = FusionEngine()
        let observations = [
            obs("screen", confidence: 0.9, summary: "writing email", ts: 1_000),
            obs("audio", confidence: 0.4, summary: "music", ts: 1_000),
        ]
        let unified = await fusion.fuse(observations, now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(unified.current, "writing email")
        XCTAssertGreaterThan(unified.confidence, 0)
    }

    func testFuseEmptyIsNeutral() async {
        let unified = await FusionEngine().fuse([], now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(unified.confidence, 0, accuracy: 1e-9)
        XCTAssertTrue(unified.recent.isEmpty)
    }

    // MARK: - Attention V2 (§76)

    func testActivityDetection() {
        let detector = ActivityDetector()
        let coding = ScreenUnderstanding(app: "Xcode", intent: "coding", entities: [],
                                         relevance: 0.7, confidence: 0.8)
        let meetingAudio = AudioUnderstanding(speaking: true, speakerCount: 3,
                                              transcriptSummary: "", confidence: 0.8)

        XCTAssertEqual(detector.detect(screen: nil, audio: nil, idleSeconds: 300, focusSeconds: 0), .idle)
        XCTAssertEqual(detector.detect(screen: nil, audio: meetingAudio, idleSeconds: 0, focusSeconds: 0), .meeting)
        XCTAssertEqual(detector.detect(screen: coding, audio: nil, idleSeconds: 0, focusSeconds: 60), .working)
        XCTAssertEqual(detector.detect(screen: coding, audio: nil, idleSeconds: 0, focusSeconds: 900), .flow)
        XCTAssertEqual(detector.detect(screen: nil, audio: nil, idleSeconds: 0, focusSeconds: 0), .thinking)
    }
}
