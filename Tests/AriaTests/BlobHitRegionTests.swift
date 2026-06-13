import XCTest
import CoreGraphics
@testable import Aria

final class BlobHitRegionTests: XCTestCase {
    // A 1440×900 main screen at the origin.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    // Blob region in SwiftUI top-left space: 184×184 box centered near bottom.
    let blob = CGRect(x: 620, y: 700, width: 184, height: 184)   // center (712, 792)

    func testCursorOverBlobCenterIsInside() {
        // SwiftUI center (712, 792) → AppKit y = 900 - 792 = 108.
        let cursor = CGPoint(x: 712, y: 108)
        XCTAssertTrue(BlobHitRegion.contains(cursorScreen: cursor, blobFrameSwiftUI: blob, screen: screen, inflation: 12))
    }

    func testCursorTopLeftCornerOfScreenIsOutside() {
        let cursor = CGPoint(x: 5, y: 895)   // SwiftUI (5,5) — far from blob
        XCTAssertFalse(BlobHitRegion.contains(cursorScreen: cursor, blobFrameSwiftUI: blob, screen: screen, inflation: 12))
    }

    func testInflationExtendsRegion() {
        // SwiftUI point (610, 792): 10pt left of the rect's left edge (620).
        let cursor = CGPoint(x: 610, y: 108)
        XCTAssertFalse(BlobHitRegion.contains(cursorScreen: cursor, blobFrameSwiftUI: blob, screen: screen, inflation: 0))
        XCTAssertTrue(BlobHitRegion.contains(cursorScreen: cursor, blobFrameSwiftUI: blob, screen: screen, inflation: 12))
    }

    func testRespectsScreenOrigin() {
        // Secondary-style screen offset by (100, 50).
        let s = CGRect(x: 100, y: 50, width: 1440, height: 900)
        // SwiftUI center maps to AppKit: x = 100 + 712, y = (50+900) - 792 = 158.
        let cursor = CGPoint(x: 812, y: 158)
        XCTAssertTrue(BlobHitRegion.contains(cursorScreen: cursor, blobFrameSwiftUI: blob, screen: s, inflation: 12))
    }
}
