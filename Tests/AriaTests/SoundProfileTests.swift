import XCTest
@testable import Aria

final class SoundProfileTests: XCTestCase {

    func testEveryKindHasACategory() {
        for kind in UISounds.Kind.allCases {
            _ = SoundProfile.category(for: kind)   // must not crash / be exhaustive
        }
    }

    func testCategoryMapping() {
        XCTAssertEqual(SoundProfile.category(for: .wake), .interaction)
        XCTAssertEqual(SoundProfile.category(for: .thinking), .thinking)
        XCTAssertEqual(SoundProfile.category(for: .task), .thinking)
        XCTAssertEqual(SoundProfile.category(for: .confirm), .success)
        XCTAssertEqual(SoundProfile.category(for: .done), .completion)
        XCTAssertEqual(SoundProfile.category(for: .error), .warning)
    }

    func testNotSilentPlaysEverything() {
        for kind in UISounds.Kind.allCases {
            XCTAssertTrue(SoundProfile.shouldPlay(kind, silentMode: false))
        }
    }

    func testSilentModeSuppressesNonWarnings() {
        XCTAssertFalse(SoundProfile.shouldPlay(.wake, silentMode: true))
        XCTAssertFalse(SoundProfile.shouldPlay(.done, silentMode: true))
        XCTAssertFalse(SoundProfile.shouldPlay(.tick, silentMode: true))
    }

    func testWarningStillPlaysInSilentMode() {
        XCTAssertTrue(SoundProfile.shouldPlay(.error, silentMode: true))   // warnings still inform
    }
}
