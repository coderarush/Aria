import XCTest
@testable import Aria

private struct ConstLegacy: LegacyExecutor {
    let output: String
    func execute(_ request: BridgeRequest) async -> BridgeResult {
        BridgeResult(output: output, success: true, duration: 0.02)
    }
}

private final class ScriptedRuntime: RuntimeExecutor, @unchecked Sendable {
    private var outputs: [BridgeResult]
    private var index = 0
    private let lock = NSLock()
    init(_ outputs: [BridgeResult]) { self.outputs = outputs }
    func execute(_ request: BridgeRequest) async -> BridgeResult {
        lock.lock(); defer { lock.unlock() }
        let result = outputs[min(index, outputs.count - 1)]
        index += 1
        return result
    }
}

final class Part3ShadowTests: XCTestCase {

    func testRunSilentlyRecordsMatch() async {
        let shadow = ShadowExecution(legacy: ConstLegacy(output: "X"),
                                     runtime: ScriptedRuntime([BridgeResult(output: "X")]),
                                     threshold: 0.95)
        let diff = await shadow.run(BridgeRequest(objective: "a"))
        XCTAssertTrue(diff.equal)
        let report = await shadow.report()
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.matches, 1)
        XCTAssertEqual(report.parity, 1.0, accuracy: 1e-9)
        XCTAssertTrue(report.meetsThreshold)
    }

    func testMismatchLowersParityBelowThreshold() async {
        let shadow = ShadowExecution(
            legacy: ConstLegacy(output: "A"),
            runtime: ScriptedRuntime([BridgeResult(output: "A"), BridgeResult(output: "B")]),
            threshold: 0.95)
        _ = await shadow.run(BridgeRequest(objective: "1"))
        _ = await shadow.run(BridgeRequest(objective: "2"))
        let report = await shadow.report()
        let promotable = await shadow.promotable()
        XCTAssertEqual(report.parity, 0.5, accuracy: 1e-9)
        XCTAssertFalse(report.meetsThreshold)
        XCTAssertFalse(promotable)
    }

    func testRuntimeErrorTracked() async {
        let shadow = ShadowExecution(
            legacy: ConstLegacy(output: "A"),
            runtime: ScriptedRuntime([BridgeResult(output: "", success: false)]),
            threshold: 0.95)
        _ = await shadow.run(BridgeRequest(objective: "1"))
        let report = await shadow.report()
        XCTAssertEqual(report.errors, 1)
        XCTAssertFalse(report.meetsThreshold)
    }

    func testEmptyReportNotPromotable() async {
        let shadow = ShadowExecution(legacy: ConstLegacy(output: "A"),
                                     runtime: ScriptedRuntime([BridgeResult(output: "A")]),
                                     threshold: 0.95)
        let promotable = await shadow.promotable()
        XCTAssertFalse(promotable)   // no runs yet
    }
}
