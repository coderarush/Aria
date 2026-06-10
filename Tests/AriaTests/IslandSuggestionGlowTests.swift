import XCTest
@testable import Aria

@MainActor
final class IslandSuggestionGlowTests: XCTestCase {

    func testSuggestionGlowToggles() {
        let vm = IslandViewModel()
        XCTAssertFalse(vm.hasSuggestion)
        vm.showSuggestionGlow()
        XCTAssertTrue(vm.hasSuggestion)
        vm.clearSuggestionGlow()
        XCTAssertFalse(vm.hasSuggestion)
    }

    func testGlowIsIndependentOfState() {
        let vm = IslandViewModel()
        vm.showSuggestionGlow()
        vm.beginListening()
        // listening state must not clobber the suggestion glow flag
        XCTAssertEqual(vm.state, .listening)
        XCTAssertTrue(vm.hasSuggestion)
    }
}
