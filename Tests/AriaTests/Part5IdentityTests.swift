import XCTest
@testable import Aria

final class Part5IdentityTests: XCTestCase {

    // MARK: - IdentityEngine (§94)

    func testDefaultProfileIsConciseAndCalm() {
        let profile = IdentityEngine().profile()
        XCTAssertEqual(profile.tone, "concise")
        XCTAssertEqual(profile.pace, "calm")
        XCTAssertTrue(profile.reliable)
        XCTAssertTrue(profile.clear)
    }

    func testNeverSimulatesEmotionOrPersonhood() {
        let engine = IdentityEngine()
        XCTAssertFalse(engine.simulatesEmotion)
        XCTAssertFalse(engine.claimsPersonhood)
    }

    func testApplyMakesTextConcise() {
        let engine = IdentityEngine()
        let result = engine.apply(toDraft: "I just really think this is very good")
        XCTAssertEqual(result, "I think this is good")
    }

    // MARK: - ProductMemory (§95)

    func testRecordIncrementsCount() async {
        let memory = ProductMemory()
        await memory.record(kind: "workflow", label: "research")
        await memory.record(kind: "workflow", label: "research")
        let top = await memory.top(kind: "workflow", limit: 5)
        XCTAssertEqual(top.first?.count, 2)
    }

    func testBoundedRetentionDropsLeastFrequent() async {
        let memory = ProductMemory(maxPatterns: 2)
        await memory.record(kind: "a", label: "one")
        await memory.record(kind: "a", label: "two")
        await memory.record(kind: "a", label: "two")   // two is more frequent
        await memory.record(kind: "a", label: "three")  // forces eviction of least frequent
        let all = await memory.top(kind: nil, limit: 10)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.label == "two" })
    }

    func testLabelTruncatedToAvoidTranscripts() async {
        let memory = ProductMemory()
        let huge = String(repeating: "x", count: 500)
        await memory.record(kind: "k", label: huge)
        let stored = await memory.top(kind: "k", limit: 1).first
        XCTAssertLessThanOrEqual(stored?.label.count ?? 999, 120)
    }
}
