import XCTest
import SwiftUI
@testable import Aria

final class ThemeTests: XCTestCase {
    func testPresetIDsResolve() {
        XCTAssertNotNil(Theme.presetColor(id: "blue"))
        XCTAssertNotNil(Theme.presetColor(id: "graphite"))
        XCTAssertNil(Theme.presetColor(id: "nope"))
    }

    func testHexParsing() {
        XCTAssertNotNil(Theme.color(fromHex: "#3B82F6"))
        XCTAssertNotNil(Theme.color(fromHex: "3B82F6"))
        XCTAssertNil(Theme.color(fromHex: "xyz"))
    }

    func testChoiceEncodingRoundTrip() {
        XCTAssertEqual(Theme.decodeChoice(Theme.encode(.system)), .system)
        XCTAssertEqual(Theme.decodeChoice(Theme.encode(.preset("teal"))), .preset("teal"))
        XCTAssertEqual(Theme.decodeChoice(Theme.encode(.custom(hex: "#FF8800"))), .custom(hex: "#FF8800"))
    }
}
