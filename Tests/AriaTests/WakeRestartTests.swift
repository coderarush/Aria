import XCTest
@testable import Aria

final class WakeRestartTests: XCTestCase {
    func testStaleCallbackDoesNotRestart() {
        var life = RecognitionLifecycle()
        let id = life.begin()              // session 1
        _ = life.begin()                   // session 2 supersedes
        XCTAssertFalse(life.shouldRestart(forSession: id))
    }
    func testCurrentSessionErrorRestarts() {
        var life = RecognitionLifecycle()
        let id = life.begin()
        XCTAssertTrue(life.shouldRestart(forSession: id))
    }
    func testWatchdogFiresOnSilence() {
        var life = RecognitionLifecycle()
        _ = life.begin()
        life.sawAudio(at: 0)
        XCTAssertFalse(life.watchdogExpired(now: 2, timeout: 5))
        XCTAssertTrue(life.watchdogExpired(now: 6, timeout: 5))
    }
}
