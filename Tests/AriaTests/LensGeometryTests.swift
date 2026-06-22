import XCTest
import CoreGraphics
@testable import Aria

final class LensGeometryTests: XCTestCase {

    func testBoundingBoxTightFitsPoints() {
        let pts = [CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 5), CGPoint(x: 25, y: 60)]
        let box = LensGeometry.boundingBox(of: pts)
        XCTAssertEqual(box.minX, 10, accuracy: 0.001)
        XCTAssertEqual(box.minY, 5, accuracy: 0.001)
        XCTAssertEqual(box.maxX, 40, accuracy: 0.001)
        XCTAssertEqual(box.maxY, 60, accuracy: 0.001)
    }

    func testBoundingBoxPaddingInflatesEverySide() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        let box = LensGeometry.boundingBox(of: pts, padding: 5)
        XCTAssertEqual(box.minX, -5, accuracy: 0.001)
        XCTAssertEqual(box.width, 20, accuracy: 0.001)
    }

    func testBoundingBoxDegenerateIsNull() {
        XCTAssertTrue(LensGeometry.boundingBox(of: []).isNull)
        XCTAssertTrue(LensGeometry.boundingBox(of: [CGPoint(x: 1, y: 1)]).isNull)
    }

    func testClampKeepsRectInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r = LensGeometry.clamp(CGRect(x: 80, y: 80, width: 40, height: 40), to: bounds)
        XCTAssertEqual(r.maxX, 100, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 100, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(r.width, 0)
    }

    func testClampFullyOutsideCollapsesNonNegative() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r = LensGeometry.clamp(CGRect(x: 200, y: 200, width: 40, height: 40), to: bounds)
        XCTAssertGreaterThanOrEqual(r.width, 0)
        XCTAssertGreaterThanOrEqual(r.height, 0)
    }

    func testPathLengthSumsSegments() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), CGPoint(x: 3, y: 4)]
        XCTAssertEqual(LensGeometry.pathLength(pts), 5, accuracy: 0.001)
    }

    func testClosedLoopDetectsCircle() {
        // 16-point circle returning near its start.
        var pts: [CGPoint] = []
        for i in 0...16 {
            let a = Double(i) / 16 * 2 * .pi
            pts.append(CGPoint(x: 50 + 40 * cos(a), y: 50 + 40 * sin(a)))
        }
        XCTAssertTrue(LensGeometry.isClosedLoop(pts))
    }

    func testOpenLineIsNotClosedLoop() {
        let pts = (0...10).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        XCTAssertFalse(LensGeometry.isClosedLoop(pts))
    }

    func testSampleAlongReturnsRequestedCount() {
        let pts = (0...10).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let s = LensGeometry.sampleAlong(pts, count: 5)
        XCTAssertEqual(s.count, 5)
        // Evenly spaced along a straight 100-wide line: monotonic increasing x.
        for i in 1..<s.count { XCTAssertGreaterThanOrEqual(s[i].x, s[i - 1].x) }
    }

    func testSampleAlongDegenerateNeverCrashes() {
        XCTAssertEqual(LensGeometry.sampleAlong([], count: 5).count, 0)
        let one = LensGeometry.sampleAlong([CGPoint(x: 1, y: 1)], count: 5)
        XCTAssertEqual(one.count, 1)   // < 2 points returned as-is
    }

    func testFractionRectNormalizesAndClamps() {
        let screen = CGSize(width: 1000, height: 500)
        let f = LensGeometry.fractionRect(CGRect(x: 500, y: 250, width: 250, height: 125), in: screen)
        XCTAssertEqual(f.minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.minY, 0.5, accuracy: 0.001)
        XCTAssertEqual(f.width, 0.25, accuracy: 0.001)
        XCTAssertEqual(f.height, 0.25, accuracy: 0.001)
    }

    func testFractionRectZeroScreenIsZero() {
        XCTAssertEqual(LensGeometry.fractionRect(.init(x: 1, y: 1, width: 1, height: 1), in: .zero), .zero)
    }
}
