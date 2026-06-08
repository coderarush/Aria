import XCTest
import CoreGraphics
@testable import Aria

final class BlobMathTests: XCTestCase {

    func testRadiiCountMatchesN() {
        XCTAssertEqual(BlobMath.radii(t: 1.0, n: 11, amp: 0.1, speed: 1).count, 11)
        XCTAssertEqual(BlobMath.radii(t: 0.0, n: 8, amp: 0.2, speed: 1).count, 8)
    }

    func testZeroAmpIsPerfectCircle() {
        let r = BlobMath.radii(t: 3.3, n: 12, amp: 0, speed: 1)
        XCTAssertTrue(r.allSatisfy { abs($0 - 1) < 1e-9 }, "amp 0 → every radius is exactly 1")
    }

    func testRadiiStayWithinAmpBounds() {
        let amp = 0.25
        let r = BlobMath.radii(t: 7.1, n: 11, amp: amp, speed: 1.4)
        // |w| <= 0.6+0.3+0.1 = 1.0, so radius is within 1 ± amp.
        XCTAssertTrue(r.allSatisfy { $0 >= CGFloat(1 - amp) - 1e-6 && $0 <= CGFloat(1 + amp) + 1e-6 })
    }

    func testDegenerateNDoesNotCrash() {
        XCTAssertEqual(BlobMath.radii(t: 1, n: 2, amp: 0.1, speed: 1).count, 2)
        XCTAssertTrue(BlobMath.radii(t: 1, n: 0, amp: 0.1, speed: 1).isEmpty)
    }

    func testEvolvesOverTime() {
        let a = BlobMath.radii(t: 1.0, n: 11, amp: 0.2, speed: 1)
        let b = BlobMath.radii(t: 2.0, n: 11, amp: 0.2, speed: 1)
        XCTAssertNotEqual(a, b, "the blob should change shape as time advances")
    }
}
