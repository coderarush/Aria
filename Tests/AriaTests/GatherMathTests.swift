import XCTest
import CoreGraphics
@testable import Aria

final class GatherMathTests: XCTestCase {
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let cr: CGFloat = 26
    let center = CGPoint(x: 500, y: 300)

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    func testStartsAtPerimeterWithNoGlow() {
        let s = GatherMath.streamer(i: 0, n: 30, progress: 0, rect: rect, cornerRadius: cr, center: center)
        XCTAssertEqual(dist(s.pos, s.start), 0, accuracy: 0.5)
        XCTAssertLessThan(s.glow, 0.01)
    }

    func testEndsAtCenterAndMergedOut() {
        let s = GatherMath.streamer(i: 7, n: 30, progress: 1, rect: rect, cornerRadius: cr, center: center)
        XCTAssertEqual(dist(s.pos, center), 0, accuracy: 0.5)
        XCTAssertLessThan(s.glow, 0.01)   // fully merged → no glow
    }

    func testMidFlightIsLitAndBetween() {
        // i=0 has zero stagger delay, so it's cleanly monotone.
        let s = GatherMath.streamer(i: 0, n: 30, progress: 0.5, rect: rect, cornerRadius: cr, center: center)
        XCTAssertGreaterThan(s.glow, 0.2)
        let dStart = dist(s.pos, s.start)
        let dCenter = dist(s.pos, center)
        XCTAssertGreaterThan(dStart, 1)    // has left the edge
        XCTAssertGreaterThan(dCenter, 1)   // not yet arrived
    }

    func testMonotonicApproachForUnstaggeredStreamer() {
        let early = GatherMath.streamer(i: 0, n: 30, progress: 0.3, rect: rect, cornerRadius: cr, center: center)
        let late  = GatherMath.streamer(i: 0, n: 30, progress: 0.7, rect: rect, cornerRadius: cr, center: center)
        XCTAssertGreaterThan(dist(early.pos, center), dist(late.pos, center))
    }

    func testStreamersStartAtDistinctPerimeterPoints() {
        let a = GatherMath.streamer(i: 0, n: 30, progress: 0, rect: rect, cornerRadius: cr, center: center).start
        let b = GatherMath.streamer(i: 15, n: 30, progress: 0, rect: rect, cornerRadius: cr, center: center).start
        XCTAssertGreaterThan(dist(a, b), 50)   // spread around the rim
    }

    func testEaseInOutCubicEndpoints() {
        XCTAssertEqual(GatherMath.easeInOutCubic(0), 0, accuracy: 1e-9)
        XCTAssertEqual(GatherMath.easeInOutCubic(1), 1, accuracy: 1e-9)
        XCTAssertEqual(GatherMath.easeInOutCubic(0.5), 0.5, accuracy: 1e-9)
    }
}
