import XCTest
import CoreGraphics
@testable import Aria

final class BorderMathTests: XCTestCase {
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let cr: CGFloat = 26

    func testStartIsTopCenter() {
        let p = BorderMath.point(u: 0, in: rect, cornerRadius: cr).point
        XCTAssertEqual(p.x, rect.midX, accuracy: 0.5)
        XCTAssertEqual(p.y, rect.minY, accuracy: 0.5)
    }

    func testHalfwayIsBottomCenter() {
        let p = BorderMath.point(u: 0.5, in: rect, cornerRadius: cr).point
        XCTAssertEqual(p.x, rect.midX, accuracy: 0.5)
        XCTAssertEqual(p.y, rect.maxY, accuracy: 0.5)
    }

    func testQuarterIsOnRightEdge() {
        let p = BorderMath.point(u: 0.25, in: rect, cornerRadius: cr).point
        // Clockwise from top-center, a quarter of the way lands on the right side.
        XCTAssertGreaterThan(p.x, rect.midX)
        XCTAssertEqual(p.x, rect.maxX, accuracy: 1.0)
    }

    func testAllPointsInsideRect() {
        for i in 0..<200 {
            let u = Double(i) / 200
            let p = BorderMath.point(u: u, in: rect, cornerRadius: cr).point
            XCTAssertGreaterThanOrEqual(p.x, rect.minX - 0.01)
            XCTAssertLessThanOrEqual(p.x, rect.maxX + 0.01)
            XCTAssertGreaterThanOrEqual(p.y, rect.minY - 0.01)
            XCTAssertLessThanOrEqual(p.y, rect.maxY + 0.01)
        }
    }

    func testUWrapsAround() {
        let a = BorderMath.point(u: 0.3, in: rect, cornerRadius: cr).point
        let b = BorderMath.point(u: 1.3, in: rect, cornerRadius: cr).point
        XCTAssertEqual(a.x, b.x, accuracy: 0.01)
        XCTAssertEqual(a.y, b.y, accuracy: 0.01)
    }

    func testNearestUForBottomCenter() {
        let bottomCenter = CGPoint(x: rect.midX, y: rect.maxY - 5)
        let u = BorderMath.nearestU(to: bottomCenter, in: rect, cornerRadius: cr)
        XCTAssertEqual(u, 0.5, accuracy: 0.02)
    }

    func testNearestUForTopCenter() {
        let topCenter = CGPoint(x: rect.midX, y: rect.minY + 5)
        let u = BorderMath.nearestU(to: topCenter, in: rect, cornerRadius: cr)
        // u=0 and u≈1 both map to top-center; accept either end.
        XCTAssertTrue(u < 0.02 || u > 0.98, "got \(u)")
    }

    func testCometIsOneAtHead() {
        XCTAssertEqual(BorderMath.cometIntensity(u: 0.4, head: 0.4, tail: 0.18), 1.0, accuracy: 1e-9)
    }

    func testCometZeroBeyondTail() {
        // 0.3 is 0.3 behind a head at 0.6 — well past an 0.18 tail.
        XCTAssertEqual(BorderMath.cometIntensity(u: 0.3, head: 0.6, tail: 0.18), 0.0, accuracy: 1e-9)
    }

    func testCometWrapsAroundZero() {
        // head just past 0, u near 1 → should still be lit (wrap).
        let v = BorderMath.cometIntensity(u: 0.98, head: 0.05, tail: 0.18)
        XCTAssertGreaterThan(v, 0)
        XCTAssertLessThanOrEqual(v, 1)
    }

    func testCometMonotonicInTail() {
        let near = BorderMath.cometIntensity(u: 0.55, head: 0.6, tail: 0.18)   // 0.05 behind
        let far  = BorderMath.cometIntensity(u: 0.48, head: 0.6, tail: 0.18)   // 0.12 behind
        XCTAssertGreaterThan(near, far)
    }
}
