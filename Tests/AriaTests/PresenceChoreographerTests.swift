import XCTest
@testable import Aria

@MainActor
final class PresenceChoreographerTests: XCTestCase {

    func testWakeFromHiddenGoesThroughBorderIn() {
        let c = PresenceChoreographer()
        XCTAssertEqual(c.kind, .hidden)
        c.setMode(.border, now: 0)
        XCTAssertEqual(c.kind, .borderIn)
        c.advance(now: 0.2)
        XCTAssertEqual(c.kind, .borderIn)
        XCTAssertEqual(c.progress(at: 0.2), 0.2 / PresenceChoreographer.dBorderIn, accuracy: 0.001)
        c.advance(now: PresenceChoreographer.dBorderIn)
        XCTAssertEqual(c.kind, .border)
    }

    func testBorderToBlobPassesThroughConsolidating() {
        let c = PresenceChoreographer()
        c.setMode(.border, now: 0); c.advance(now: 1)         // settled border
        XCTAssertEqual(c.kind, .border)
        c.setMode(.blob, now: 1)
        XCTAssertEqual(c.kind, .consolidating)
        // Border intensity drains as the blob pools (pure function of the clock).
        let mid = 1 + PresenceChoreographer.dConsolidate * 0.5
        c.advance(now: mid)
        XCTAssertEqual(c.borderIntensity(at: mid), 0.5, accuracy: 0.05)
        XCTAssertTrue(c.showsBlob)
        c.advance(now: 1 + PresenceChoreographer.dConsolidate)
        XCTAssertEqual(c.kind, .blob)
    }

    func testBlobToBorderSplashesThenIgnites() {
        let c = PresenceChoreographer()
        c.setMode(.blob, now: 0)                               // enters via blobIn
        c.advance(now: PresenceChoreographer.dBlobIn)          // settles to blob
        XCTAssertEqual(c.kind, .blob)
        let t0 = PresenceChoreographer.dBlobIn
        c.setMode(.border, now: t0)                            // legacy border path still works
        XCTAssertEqual(c.kind, .splashing)
        let half = t0 + PresenceChoreographer.dSplash * 0.5
        c.advance(now: half)
        XCTAssertGreaterThan(c.blobFall(at: half), 0)
        XCTAssertTrue(c.showsBlob)
        // splash completes → chains into igniting (NOT straight to border)
        c.advance(now: t0 + PresenceChoreographer.dSplash)
        XCTAssertEqual(c.kind, .igniting)
        XCTAssertNotNil(c.borderSweep(at: t0 + PresenceChoreographer.dSplash))
        // ignite completes → border
        c.advance(now: t0 + PresenceChoreographer.dSplash + PresenceChoreographer.dIgnite)
        XCTAssertEqual(c.kind, .border)
        XCTAssertNil(c.borderSweep(at: t0 + PresenceChoreographer.dSplash + PresenceChoreographer.dIgnite))
    }

    func testDismissGoesToHidden() {
        let c = PresenceChoreographer()
        c.setMode(.blob, now: 0)
        c.advance(now: PresenceChoreographer.dBlobIn)          // settle entrance → blob
        c.setMode(.hidden, now: PresenceChoreographer.dBlobIn)
        XCTAssertEqual(c.kind, .dismissing)
        c.advance(now: PresenceChoreographer.dBlobIn + PresenceChoreographer.dDismiss)
        XCTAssertEqual(c.kind, .hidden)
    }

    func testHiddenToBlobEntersViaBlobIn() {
        let c = PresenceChoreographer()
        c.setMode(.blob, now: 0)
        XCTAssertEqual(c.kind, .blobIn)                        // spring entrance, not instant
        XCTAssertTrue(c.showsBlob)                             // blob is drawn during the entrance
        c.advance(now: PresenceChoreographer.dBlobIn)
        XCTAssertEqual(c.kind, .blob)
    }

    func testNoOpWhenTargetUnchanged() {
        let c = PresenceChoreographer()
        c.setMode(.border, now: 0)
        c.advance(now: 1)                                      // border
        c.setMode(.border, now: 2)                            // same target
        XCTAssertEqual(c.kind, .border)
    }

    func testTransitionOwnsTimelineUntilSettled() {
        // A target change mid-borderIn does not interrupt the in-flight phase.
        let c = PresenceChoreographer()
        c.setMode(.border, now: 0)
        c.setMode(.blob, now: 0.1)                            // flips target mid-borderIn
        XCTAssertEqual(c.kind, .borderIn)                    // still finishing borderIn
        c.advance(now: PresenceChoreographer.dBorderIn)      // settles to border, reconciles → consolidating
        XCTAssertEqual(c.kind, .consolidating)
    }

    func testProgressIsPureNoAdvanceNeeded() {
        // Progress is read straight off the clock — no per-frame advance() call
        // mutates state, which is what keeps the motion smooth.
        let c = PresenceChoreographer()
        c.setMode(.border, now: 100)
        XCTAssertEqual(c.progress(at: 100 + PresenceChoreographer.dBorderIn * 0.25), 0.25, accuracy: 0.001)
        XCTAssertEqual(c.progress(at: 100 + PresenceChoreographer.dBorderIn * 0.75), 0.75, accuracy: 0.001)
    }
}
