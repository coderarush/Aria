import Foundation

/// One labelled perception case (spec §84).
struct PerceptionScenario: Sendable {
    let observation: Observation
    let expectedRelevant: Bool
}

/// Aggregate perception quality (spec §84).
struct PerceptionReport: Sendable {
    let total: Int
    let correct: Int
    let target: Double

    var relevanceRate: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    var meetsTarget: Bool { total > 0 && relevanceRate >= target }
}

/// Measures perceived relevance (spec §84): a scenario is judged correct when
/// the engine's admit/reject decision matches the expected relevance. Target is
/// 95% perceived relevance.
actor PerceptionHarness {

    private let perception: PerceptionEngine
    private let target: Double

    init(perception: PerceptionEngine, target: Double = 0.95) {
        self.perception = perception
        self.target = target
    }

    func evaluate(_ scenarios: [PerceptionScenario]) async -> PerceptionReport {
        var correct = 0
        for scenario in scenarios {
            let admitted = await perception.ingest(scenario.observation)
            if admitted == scenario.expectedRelevant { correct += 1 }
        }
        return PerceptionReport(total: scenarios.count, correct: correct, target: target)
    }
}
