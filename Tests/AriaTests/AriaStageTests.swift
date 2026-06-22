import XCTest
import CoreGraphics
@testable import Aria

@MainActor
final class AriaStageTests: XCTestCase {
    func testSetWorkersClampsAndReplaces() {
        let stage = AriaStage.shared
        stage.clearWorkers()
        stage.setWorkers(count: 3)
        XCTAssertEqual(stage.workers.count, 3)
        stage.setWorkers(count: 1)            // shrink
        XCTAssertEqual(stage.workers.count, 1)
        stage.setWorkers(count: 99)           // clamp to 8
        XCTAssertEqual(stage.workers.count, 8)
        stage.setWorkers(count: 0)            // dismiss
        XCTAssertTrue(stage.workers.isEmpty)
    }

    func testPointAddsMarkerWithCoordinates() {
        let stage = AriaStage.shared
        stage.clearMarkers()
        stage.point(at: CGPoint(x: 120, y: 80), label: "Export", ttl: 100)
        XCTAssertEqual(stage.markers.count, 1)
        XCTAssertEqual(stage.markers[0].point, CGPoint(x: 120, y: 80))
        XCTAssertEqual(stage.markers[0].label, "Export")
        XCTAssertTrue(stage.isActive)
        stage.clearMarkers()
        XCTAssertFalse(stage.isActive)
    }
}
