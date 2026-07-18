import XCTest
@testable import Aria

final class Part4ContextEnginesTests: XCTestCase {

    private func perception() -> (PerceptionEngine, PerceptionStore) {
        let store = PerceptionStore(maxRetained: 100)
        let engine = PerceptionEngine(bus: ObservationBus(), store: store,
                                      policy: ObservationPolicy(minConfidence: 0, maxRetained: 100))
        return (engine, store)
    }

    // MARK: - ScreenContextEngine (§72) — structured only, no screenshots

    func testScreenUnderstandingDerivesIntentAndStoresStructured() async {
        let (perception, store) = perception()
        let screen = ScreenContextEngine(perception: perception)
        let understanding = await screen.observe(app: "Mail", windowTitle: "Compose",
                                                 extractedText: "Dear Alice")
        XCTAssertEqual(understanding.intent, "writing")
        XCTAssertTrue(understanding.entities.contains("Alice"))

        let stored = await store.all(source: "screen")
        XCTAssertEqual(stored.count, 1)
        // Privacy: structured summary only — never a screenshot blob.
        XCTAssertNotNil(stored.first?.payload["app"])
        XCTAssertNil(stored.first?.payload["screenshot"])
    }

    // MARK: - AudioContextEngine (§73) — no raw audio

    func testAudioUnderstandingSummarizesWithoutRawAudio() async {
        let (perception, store) = perception()
        let audio = AudioContextEngine(perception: perception)
        let understanding = await audio.observe(transcript: "hello there team", speakerCount: 2)
        XCTAssertTrue(understanding.speaking)
        XCTAssertEqual(understanding.speakerCount, 2)

        let stored = await store.all(source: "audio")
        XCTAssertEqual(stored.count, 1)
        XCTAssertNil(stored.first?.payload["rawAudio"])
    }

    // MARK: - VisualContextEngine (§74) — change detection, no recording

    func testVisualChangeDetection() async {
        let (perception, _) = perception()
        let visual = VisualContextEngine(perception: perception)
        _ = await visual.observe(objects: ["laptop", "mug"])
        let same = await visual.observe(objects: ["laptop", "mug"])
        XCTAssertFalse(same.changed)
        let different = await visual.observe(objects: ["phone"])
        XCTAssertTrue(different.changed)
    }
}
