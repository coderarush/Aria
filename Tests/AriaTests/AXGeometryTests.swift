import XCTest
import ApplicationServices
@testable import Aria

final class AXGeometryTests: XCTestCase {

    func testPointAndSizeParseAXValues() {
        var point = CGPoint(x: 12.5, y: 34.25)
        var size = CGSize(width: 320, height: 240)

        let pointValue = AXValueCreate(.cgPoint, &point)
        let sizeValue = AXValueCreate(.cgSize, &size)

        XCTAssertEqual(AXGeometry.point(from: pointValue), point)
        XCTAssertEqual(AXGeometry.size(from: sizeValue), size)
    }

    func testPointAndSizeRejectInvalidValues() {
        let invalid: CFTypeRef = "not-ax-value" as CFString

        XCTAssertNil(AXGeometry.element(from: invalid))
        XCTAssertNil(AXGeometry.element(from: nil))
        XCTAssertNil(AXGeometry.point(from: invalid))
        XCTAssertNil(AXGeometry.size(from: invalid))
        XCTAssertNil(AXGeometry.point(from: nil))
        XCTAssertNil(AXGeometry.size(from: nil))
    }
}
