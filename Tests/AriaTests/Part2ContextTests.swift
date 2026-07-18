import XCTest
@testable import Aria

private struct FixedContext: ContextContributor {
    let apps: [String]
    let activity: String?
    func contribute(to snapshot: inout Domain.ContextSnapshot) async {
        snapshot.apps.append(contentsOf: apps)
        if let activity { snapshot.activity = activity }
    }
}

final class Part2ContextTests: XCTestCase {

    func testAssembleCapturesCurrentAndDerives() async {
        let collector = ContextCollector(eventBus: EventBus())
        await collector.addSource(FixedContext(apps: ["Mail"], activity: "writing"))
        let assembler = ContextAssembler(collector: collector)

        let envelope = await assembler.assemble()
        XCTAssertEqual(envelope.current.apps, ["Mail"])
        XCTAssertTrue(envelope.recommended.contains("review:Mail"))
        XCTAssertTrue(envelope.predicted.contains("continue:writing"))
        XCTAssertGreaterThan(envelope.confidence.value, 0)
    }

    func testHistoryAccumulatesAcrossAssembles() async {
        let collector = ContextCollector(eventBus: EventBus())
        await collector.addSource(FixedContext(apps: ["Safari"], activity: nil))
        let assembler = ContextAssembler(collector: collector)

        _ = await assembler.assemble()
        let second = await assembler.assemble()
        XCTAssertEqual(second.recent.count, 1)
    }

    func testConfidenceIsLowWithoutSignals() async {
        let collector = ContextCollector(eventBus: EventBus())
        let assembler = ContextAssembler(collector: collector)
        let envelope = await assembler.assemble()
        XCTAssertEqual(envelope.confidence.value, 0, accuracy: 1e-9)
        XCTAssertEqual(envelope.confidence.level, .low)
    }
}
