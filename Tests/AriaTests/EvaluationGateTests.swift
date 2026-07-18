import XCTest
@testable import Aria

private struct EvaluationGateNoopTool: ExecutableTool {
    let name = "noop"

    func execute(_ action: Domain.Action) async throws -> Domain.Artifact? {
        Domain.Artifact(kind: .other, reference: "evaluation")
    }
}

final class EvaluationGateTests: XCTestCase {
    private func outcome(_ name: String, status: ExecutionContract.Status,
                         verified: Bool = true) -> EvaluationScenarioOutcome {
        EvaluationScenarioOutcome(name: name, kind: .writing, status: status,
                                  verificationPassed: verified, durationMs: 12)
    }

    func testGatePassesAtThresholdWhenRequiredScenarioPassed() {
        let summary = EvaluationSummary(
            total: 2, completed: 1, avgDurationMs: 12,
            outcomes: [outcome("safe-fallback", status: .completed),
                       outcome("optional", status: .failed, verified: false)])

        let gate = summary.releaseGate(minimumCompletionRate: 0.5,
                                       requiredScenarioNames: ["safe-fallback"])

        XCTAssertTrue(gate.passed)
        XCTAssertTrue(gate.report.contains("PASS"))
    }

    func testGateFailsWhenRequiredScenarioFailedOrMissing() {
        let summary = EvaluationSummary(
            total: 2, completed: 2, avgDurationMs: 12,
            outcomes: [outcome("safe-fallback", status: .completed),
                       outcome("recovery", status: .completed, verified: false)])

        let gate = summary.releaseGate(minimumCompletionRate: 1,
                                       requiredScenarioNames: ["recovery", "unavailable-dependency"])

        XCTAssertFalse(gate.passed)
        XCTAssertTrue(gate.report.contains("recovery"))
        XCTAssertTrue(gate.report.contains("unavailable-dependency"))
    }

    func testDeterministicScenarioSuitePassesReleaseGate() async {
        let eventBus = EventBus()
        let execution = ExecutionEngine(eventBus: eventBus)
        await execution.register(EvaluationGateNoopTool())
        let coordinator = Coordinator(
            execution: execution,
            verifier: Verifier(),
            memory: MemoryEngine(eventBus: eventBus, scorer: ImportanceScorer(threshold: 0)),
            eventBus: eventBus
        )
        let summary = await EvaluationHarness(coordinator: coordinator).run(ScenarioLibrary.standard())

        let gate = summary.releaseGate(
            minimumCompletionRate: 1,
            requiredScenarioNames: Scenario.Kind.allCases.map(\.rawValue)
        )

        XCTAssertTrue(gate.passed, gate.report)
    }
}
