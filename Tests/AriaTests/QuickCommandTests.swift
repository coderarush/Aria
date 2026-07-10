import XCTest
@testable import Aria

final class QuickCommandTests: XCTestCase {

    // MARK: Volume

    func testVolumeExplicitNumbers() {
        XCTAssertEqual(QuickCommand.match("set volume to 40"), .setVolume(40))
        XCTAssertEqual(QuickCommand.match("volume 70"), .setVolume(70))
        XCTAssertEqual(QuickCommand.match("set the volume to 100"), .setVolume(100))
        XCTAssertEqual(QuickCommand.match("volume 25 percent"), .setVolume(25))
    }

    func testVolumeNumberWordsAndRelative() {
        XCTAssertEqual(QuickCommand.match("set volume to fifty"), .setVolume(50))
        XCTAssertEqual(QuickCommand.match("volume max"), .setVolume(100))
        XCTAssertEqual(QuickCommand.match("set volume to half"), .setVolume(50))
        XCTAssertEqual(QuickCommand.match("turn the volume up"), .setVolume(-1))   // up sentinel
        XCTAssertEqual(QuickCommand.match("volume down"), .setVolume(-2))          // down sentinel
    }

    func testVolumeClampsOutOfRange() {
        XCTAssertEqual(QuickCommand.match("set volume to 150"), .setVolume(100))
    }

    func testMuteUnmute() {
        XCTAssertEqual(QuickCommand.match("mute"), .setMuted(true))
        XCTAssertEqual(QuickCommand.match("be quiet"), .setMuted(true))
        XCTAssertEqual(QuickCommand.match("unmute"), .setMuted(false))
    }

    func testVolumeQuestionDoesNotFire() {
        // "what's my volume" must NOT set anything — it's a question for the model.
        XCTAssertNil(QuickCommand.match("what's my volume"))
        XCTAssertNil(QuickCommand.match("why is the volume so quiet on this laptop"))
    }

    func testCompoundVolumeRequestFallsThrough() {
        XCTAssertNil(QuickCommand.match("turn the volume up and play music"))
        XCTAssertNil(QuickCommand.match("set volume to half then open Spotify"))
    }

    // MARK: Timer

    func testTimerVariants() {
        XCTAssertEqual(QuickCommand.match("set a timer for 10 minutes"),
                       .startTimer(seconds: 600, label: "10m timer"))
        XCTAssertEqual(QuickCommand.match("timer for 90 seconds"),
                       .startTimer(seconds: 90, label: "1m 30s timer"))
        XCTAssertEqual(QuickCommand.match("set a timer for five minutes"),
                       .startTimer(seconds: 300, label: "5m timer"))
    }

    func testReminderWithContentFallsThrough() {
        // Carries content → needs the model, must not be an instant timer.
        XCTAssertNil(QuickCommand.match("remind me to call mom in 10 minutes"))
    }

    // MARK: Open URL

    func testOpenURL() {
        XCTAssertEqual(QuickCommand.match("open github.com"), .openURL("https://github.com"))
        XCTAssertEqual(QuickCommand.match("go to youtube.com/feed"), .openURL("https://youtube.com/feed"))
        XCTAssertEqual(QuickCommand.match("visit https://apple.com"), .openURL("https://apple.com"))
    }

    func testOpenURLRejectsNonDomains() {
        XCTAssertNotEqual(QuickCommand.match("open my notes"), .openURL("https://my notes"))
        XCTAssertNil(QuickCommand.match("open the door"))
    }

    // MARK: Open app

    func testOpenApp() {
        XCTAssertEqual(QuickCommand.match("open Spotify"), .openApp("Spotify"))
        XCTAssertEqual(QuickCommand.match("launch Google Chrome"), .openApp("Google Chrome"))
        XCTAssertEqual(QuickCommand.match("open Activity Monitor"), .openApp("Activity Monitor"))
    }

    func testOpenAppRejectsMultiStepAndObjects() {
        // These must reach the model, not the instant path.
        XCTAssertNil(QuickCommand.match("open Spotify and play lofi"))
        XCTAssertNil(QuickCommand.match("open Safari then search for cats"))
        XCTAssertNil(QuickCommand.match("open a new tab"))
        XCTAssertNil(QuickCommand.match("open the file I downloaded"))
    }

    // MARK: Conversation must never be hijacked

    func testConversationalRequestsFallThrough() {
        XCTAssertNil(QuickCommand.match("what's the weather in Tokyo"))
        XCTAssertNil(QuickCommand.match("write an email to my boss"))
        XCTAssertNil(QuickCommand.match("summarize this article"))
        XCTAssertNil(QuickCommand.match("how do I center a div"))
        XCTAssertNil(QuickCommand.match(""))
    }

    // MARK: Number-word helpers

    func testNumberWordNormalization() {
        XCTAssertEqual(QuickCommand.normalizeNumberWords("ten minutes"), "10 minutes")
        XCTAssertEqual(QuickCommand.numberWord("ninety"), 90)
        XCTAssertNil(QuickCommand.numberWord("banana"))
    }
}

final class AutonomousModeTests: XCTestCase {
    // Autonomous mode maps onto the existing trust primitive: when the user is
    // NOT confirming destructive actions, important-irreversible ones auto-run.
    func testConfirmOffAutoApprovesImportantIrreversible() {
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .importantIrreversible, confirmsDestructive: false),
            .auto)
    }
    func testConfirmOnStillAsks() {
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .importantIrreversible, confirmsDestructive: true),
            .ask)
    }
    func testReversibleAlwaysAuto() {
        XCTAssertEqual(
            TrustProfile.advisedLevel(importance: .reversible, confirmsDestructive: true),
            .auto)
    }
}
