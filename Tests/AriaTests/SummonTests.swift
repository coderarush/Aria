import XCTest
import Carbon.HIToolbox
@testable import Aria

@MainActor
final class SummonTests: XCTestCase {

    func testSummonFiresOnWake() {
        let engine = WakeWordEngine()
        var woke = false
        engine.onWake = { woke = true }
        engine.summon()
        XCTAssertTrue(woke)
    }

    func testSummonIgnoredWhileSuspended() {
        let engine = WakeWordEngine()
        var woke = false
        engine.onWake = { woke = true }
        engine.isSuspended = true
        engine.summon()
        XCTAssertFalse(woke, "summon must not fire while Aria is speaking")
    }

    func testSummonIgnoredMidCommandCapture() {
        let engine = WakeWordEngine()
        var wakes = 0
        engine.onWake = { wakes += 1 }
        engine.summon()
        engine.summon()   // already capturing — second press is a no-op
        XCTAssertEqual(wakes, 1)
    }
}

final class HotkeyMapTests: XCTestCase {
    func testDefaultIsOptionSpace() {
        XCTAssertEqual(HotkeyManager.defaultKeyCode, 49)            // kVK_Space
        XCTAssertEqual(HotkeyManager.defaultModifiers, UInt32(optionKey))
    }
}
