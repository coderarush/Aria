import XCTest
@testable import Aria

final class Part6MigrationControllerTests: XCTestCase {

    private func parity(matches: Int, total: Int = 100, errors: Int = 0) -> ParityReport {
        ParityReport(total: total, matches: matches, errors: errors,
                     avgOldDuration: 0.02, avgNewDuration: 0.01, threshold: 0.95)
    }

    func testStageProgression() {
        XCTAssertEqual(MigrationController.next(after: .legacy), .shadow)
        XCTAssertEqual(MigrationController.next(after: .runtimeOnly), .cleanup)
        XCTAssertEqual(MigrationController.next(after: .cleanup), .cleanup)
        XCTAssertEqual(MigrationController.previous(before: .preferred), .dual)
        XCTAssertEqual(MigrationController.previous(before: .legacy), .legacy)
    }

    func testPromoteWhenParityMeetsThreshold() async {
        let controller = MigrationController(stage: .shadow)
        let decision = await controller.decide(parity: parity(matches: 96))
        XCTAssertEqual(decision.action, .promote)
        XCTAssertEqual(decision.to, .dual)
    }

    func testHoldWhenParityInsufficient() async {
        let controller = MigrationController(stage: .shadow)
        let decision = await controller.decide(parity: parity(matches: 70))
        XCTAssertEqual(decision.action, .hold)
    }

    func testRollbackWhenParityCollapses() async {
        let controller = MigrationController(stage: .preferred)
        let decision = await controller.decide(parity: parity(matches: 30))
        XCTAssertEqual(decision.action, .rollback)
        XCTAssertEqual(decision.to, .dual)
    }

    func testApplyAdvancesStage() async {
        let controller = MigrationController(stage: .shadow)
        let decision = await controller.decide(parity: parity(matches: 99))
        await controller.apply(decision)
        let stage = await controller.stage
        XCTAssertEqual(stage, .dual)
    }
}
