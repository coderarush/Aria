import XCTest
import SwiftUI
@testable import Aria

@MainActor
final class IslandViewModelTests: XCTestCase {
    func testListeningMakesVisible() {
        let vm = IslandViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isVisible)
        vm.beginListening()
        XCTAssertEqual(vm.state, .listening)
        XCTAssertTrue(vm.isVisible)
    }

    func testResponseSetsTextAndState() {
        let vm = IslandViewModel()
        vm.beginListening()
        vm.showResponse("On it.")
        XCTAssertEqual(vm.state, .responding)
        XCTAssertEqual(vm.responseText, "On it.")
    }

    func testDismissHidesAndClears() {
        let vm = IslandViewModel()
        vm.beginListening()
        vm.showResponse("Done.")
        vm.dismiss()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isVisible)
    }
}
