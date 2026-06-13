import XCTest
@testable import Aria

@MainActor
final class PresenceChoreographerTests: XCTestCase {

    func testWakeFromHiddenGoesThroughBorderIn() {
        let c = PresenceChoreographer()
        XCTAssertEqual(c.phase.kind, .hidden)
        c.setMode(.border, now: 0)
        XCTAssertEqual(c.phase.kind, .borderIn)
        c.advance(now: 0.2)
        XCTAssertEqual(c.phase.kind, .borderIn)
        XCTAssertEqual(c.phase.progress, 0.2 / PresenceChoreographer.dBorderIn, accuracy: 0.001)
        c.advance(now: PresenceChoreographer.dBorderIn)
        XCTAssertEqual(c.phase.kind, .border)
    }

    func testBorderToBlobPassesThroughConsolidating() {
        let c = PresenceChoreographer()
        c.setMode(.border, now: 0); c.advance(now: 1)         // settled border
        XCTAssertEqual(c.phase.kind, .border)
        c.setMode(.blob, now: 1)
        XCTAssertEqual(c.phase.kind, .consolidating)
        // Border intensity drains as the blob pools.
        c.advance(now: 1 + PresenceChoreographer.dConsolidate * 0.5)
        XCTAssertEqual(c.borderIntensity, 0.5, accuracy: 0.05)
        XCTAssertTrue(c.showsBlob)
        c.advance(now: 1 + PresenceChoreographer.dConsolidate)
        XCTAssertEqual(c.phase.kind, .blob)
    }

    func testBlobToBorderSplashesThenIgnites() {
        let c = PresenceChoreographer()
        c.setMode(.blob, now: 0)                               // blob settled directly
        XCTAssertEqual(c.phase.kind, .blob)
        c.setMode(.border, now: 0)
        XCTAssertEqual(c.phase.kind, .splashing)
        c.advance(now: PresenceChoreographer.dSplash * 0.5)
        XCTAssertGreaterThan(c.blobFall, 0)
        XCTAssertTrue(c.showsBlob)
        // splash completes → chains into igniting (NOT straight to border)
        c.advance(now: PresenceChoreographer.dSplash)
        XCTAssertEqual(c.phase.kind, .igniting)
        XCTAssertNotNil(c.borderSweep)
        // ignite completes → border
        c.advance(now: PresenceChoreographer.dSplash + PresenceChoreographer.dIgnite)
        XCTAssertEqual(c.phase.kind, .border)
        XCTAssertNil(c.borderSweep)
    }

    func testDismissGoesToHidden() {
        let c = PresenceChoreographer()
        c.setMode(.blob, now: 0)
        c.setMode(.hidden, now: 0)
        XCTAssertEqual(c.phase.kind, .dismissing)
        c.advance(now: PresenceChoreographer.dDismiss)
        XCTAssertEqual(c.phase.kind, .hidden)
    }

    func testHiddenToBlobPopsInDirectly() {
        let c = PresenceChoreographer()
        c.setMode(.blob, now: 0)
        XCTAssertEqual(c.phase.kind, .blob)
        XCTAssertTrue(c.showsBlob)
    }

    func testNoOpWhenTargetUnchanged() {
        let c = PresenceChoreographer()
        c.setMode(.border, now: 0)
        c.advance(now: 1)                                      // border
        c.setMode(.border, now: 2)                            // same target
        XCTAssertEqual(c.phase.kind, .border)
    }

    func testTransitionOwnsTimelineUntilSettled() {
        // A target change mid-borderIn does not interrupt the in-flight phase.
        let c = PresenceChoreographer()
        c.setMode(.border, now: 0)
        c.setMode(.blob, now: 0.1)                            // flips target mid-borderIn
        XCTAssertEqual(c.phase.kind, .borderIn)              // still finishing borderIn
        c.advance(now: PresenceChoreographer.dBorderIn)      // settles to border, reconciles → consolidating
        XCTAssertEqual(c.phase.kind, .consolidating)
    }
}
