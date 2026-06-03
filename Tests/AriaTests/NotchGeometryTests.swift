import XCTest
import CoreGraphics
@testable import Aria

final class NotchGeometryTests: XCTestCase {
    func testPanelFrameIsHorizontallyCenteredAndTopPinned() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900) // bottom-left origin
        let size = CGSize(width: 320, height: 64)
        let frame = NotchGeometry.panelFrame(screenFrame: screen, size: size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.5) // top pinned
        XCTAssertEqual(frame.width, 320, accuracy: 0.5)
        XCTAssertEqual(frame.height, 64, accuracy: 0.5)
    }

    func testHasNotch() {
        XCTAssertTrue(NotchGeometry.hasNotch(topInset: 38))
        XCTAssertFalse(NotchGeometry.hasNotch(topInset: 0))
    }
}
