import XCTest
@testable import Aria

final class AECBypassTests: XCTestCase {

    func testBypassWhenIdleLongAfterPlayback() {
        // No far audio queued and playback ended long ago → skip the filter.
        XCTAssertTrue(AudioBus.shouldBypassAEC(farQueued: false,
                                               now: 100, lastPlaybackActivity: 90))
    }

    func testNoBypassWhileFarAudioQueued() {
        XCTAssertFalse(AudioBus.shouldBypassAEC(farQueued: true,
                                                now: 100, lastPlaybackActivity: 0))
    }

    func testNoBypassDuringEchoTail() {
        // Within the tail window after playback the room still carries her
        // voice — the filter must keep running so barge-in stays clean.
        XCTAssertFalse(AudioBus.shouldBypassAEC(farQueued: false,
                                                now: 100, lastPlaybackActivity: 99))
        XCTAssertFalse(AudioBus.shouldBypassAEC(farQueued: false,
                                                now: 100, lastPlaybackActivity: 98.5))
    }

    func testFreshLaunchNeverPlayedBypasses() {
        XCTAssertTrue(AudioBus.shouldBypassAEC(farQueued: false,
                                               now: 5, lastPlaybackActivity: 0))
    }
}
