import XCTest
@testable import Aria

final class RoutingLogTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("routing-\(UUID().uuidString).json")
    }

    func testRecordsAndReturnsNewestFirst() async {
        let log = RoutingLog(fileURL: tempURL())
        await log.record(RoutingDecision(taskClass: .fileOps, tier: .local, reason: "a"))
        await log.record(RoutingDecision(taskClass: .deepResearch, tier: .cloud, reason: "b"))
        let recent = await log.recent(10)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.decision.taskClass, .deepResearch)
    }

    func testCapsAtLimit() async {
        let log = RoutingLog(fileURL: tempURL(), cap: 5)
        for i in 0..<12 {
            await log.record(RoutingDecision(taskClass: .simpleChat, tier: .cloud, reason: "r\(i)"))
        }
        let recent = await log.recent(100)
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.first?.decision.reason, "r11")
    }

    func testPersistsAcrossInstances() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log1 = RoutingLog(fileURL: url)
        await log1.record(RoutingDecision(taskClass: .memory, tier: .local, reason: "kept"))
        let log2 = RoutingLog(fileURL: url)
        let recent = await log2.recent(10)
        XCTAssertEqual(recent.first?.decision.reason, "kept")
    }

    func testSurvivesCorruptFile() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("][garbage".utf8).write(to: url)
        let log = RoutingLog(fileURL: url)
        let recent = await log.recent(10)
        XCTAssertTrue(recent.isEmpty)
    }
}
