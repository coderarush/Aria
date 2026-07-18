import XCTest
@testable import Aria

final class Part2ProjectTests: XCTestCase {

    private func activeObjective(priority: Domain.Priority, createdAt: TimeInterval) -> Domain.Objective {
        var o = Domain.Objective(title: "o", intent: "o", priority: priority,
                                 createdAt: Date(timeIntervalSince1970: createdAt))
        o.start()
        return o
    }

    // MARK: - ObjectiveTracker (§33)

    func testTrackExposesActiveObjectives() async {
        let tracker = ObjectiveTracker()
        let active = activeObjective(priority: .normal, createdAt: 1)
        let idle = Domain.Objective(title: "idle", intent: "idle")
        await tracker.track(active)
        await tracker.track(idle)
        let result = await tracker.active()
        XCTAssertEqual(result.map(\.id), [active.id])
    }

    func testPrioritizedOrdersByPriorityThenAge() async {
        let tracker = ObjectiveTracker()
        let highNew = activeObjective(priority: .high, createdAt: 100)
        let highOld = activeObjective(priority: .high, createdAt: 50)
        let critical = activeObjective(priority: .critical, createdAt: 200)
        await tracker.track(highNew)
        await tracker.track(highOld)
        await tracker.track(critical)
        let order = await tracker.prioritized().map(\.id)
        XCTAssertEqual(order, [critical.id, highOld.id, highNew.id])
    }

    func testAgeComputed() async throws {
        let tracker = ObjectiveTracker()
        let o = activeObjective(priority: .normal, createdAt: 1_000)
        await tracker.track(o)
        let age = await tracker.ageInSeconds(of: o.id, asOf: Date(timeIntervalSince1970: 1_500))
        XCTAssertEqual(try XCTUnwrap(age), 500, accuracy: 0.001)
    }

    // MARK: - ProjectEngine (§34)

    func testCreateAndAccumulate() async {
        let engine = ProjectEngine(eventBus: EventBus())
        var project = await engine.create(name: "Essays", deadline: nil)
        await engine.addObjective(UUID(), to: project.id)
        await engine.addObjective(UUID(), to: project.id)
        await engine.addArtifact(UUID(), to: project.id)
        project = await engine.get(project.id)!
        XCTAssertEqual(project.objectiveIDs.count, 2)
        XCTAssertEqual(project.artifactIDs.count, 1)
    }

    func testSummarizeCountsContents() async {
        let engine = ProjectEngine(eventBus: EventBus())
        let project = await engine.create(name: "Startup", deadline: nil)
        await engine.addObjective(UUID(), to: project.id)
        await engine.addObjective(UUID(), to: project.id)
        await engine.addArtifact(UUID(), to: project.id)
        let summary = await engine.summarize(project.id)
        XCTAssertTrue(summary.contains("2 objectives"))
        XCTAssertTrue(summary.contains("1 artifacts"))
    }

    func testCloseRemovesFromOpen() async {
        let engine = ProjectEngine(eventBus: EventBus())
        let project = await engine.create(name: "Done", deadline: nil)
        await engine.close(project.id)
        let open = await engine.open()
        XCTAssertTrue(open.isEmpty)
        let stored = await engine.get(project.id)
        XCTAssertEqual(stored?.status, .closed)
    }
}
