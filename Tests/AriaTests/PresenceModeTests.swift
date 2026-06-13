import XCTest
import SwiftUI
@testable import Aria

@MainActor
final class PresenceModeTests: XCTestCase {
    func testIdleInvisibleIsHidden() {
        XCTAssertEqual(PresenceMode.from(state: .idle, visible: false, hasSuggestion: false), .hidden)
    }

    func testIdleWithSuggestionIsBlob() {
        XCTAssertEqual(PresenceMode.from(state: .idle, visible: true, hasSuggestion: true), .blob)
    }

    func testListeningIsBorder() {
        XCTAssertEqual(PresenceMode.from(state: .listening, visible: true, hasSuggestion: false), .border)
    }

    func testThinkingIsBlob() {
        XCTAssertEqual(PresenceMode.from(state: .thinking, visible: true, hasSuggestion: false), .blob)
    }

    func testExecutingIsBorder() {
        XCTAssertEqual(PresenceMode.from(state: .executing, visible: true, hasSuggestion: false), .border)
    }

    func testRespondingIsBlob() {
        XCTAssertEqual(PresenceMode.from(state: .responding, visible: true, hasSuggestion: false), .blob)
    }

    func testErrorIsBlob() {
        XCTAssertEqual(PresenceMode.from(state: .error, visible: true, hasSuggestion: false), .blob)
    }

    func testNotVisibleNoSuggestionAlwaysHidden() {
        for s in [IslandViewModel.State.listening, .thinking, .executing, .responding, .error] {
            XCTAssertEqual(PresenceMode.from(state: s, visible: false, hasSuggestion: false), .hidden)
        }
    }
}
