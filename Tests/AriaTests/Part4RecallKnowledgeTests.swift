import XCTest
@testable import Aria

final class Part4RecallKnowledgeTests: XCTestCase {

    // MARK: - RecallEngine (§81)

    func testRecallReconstructsWorkInProgress() async {
        let bus = EventBus()
        let continuity = ContinuityEngine(eventBus: bus)
        let memory = MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0))
        let objective = UUID()
        _ = await continuity.checkpoint(objectiveID: objective, kind: .milestone,
                                        tools: ["draft"], state: .executing)
        await memory.store(MemoryRecord(type: .project, importance: 0.9,
                                        objectiveID: objective, summary: "writing essay"))

        let recall = RecallEngine(continuity: continuity, memory: memory)
        let bundle = await recall.recall()
        XCTAssertEqual(bundle.recentActions, ["draft"])
        XCTAssertTrue(bundle.summary.contains("writing essay"))
    }

    func testRecallNothingInProgress() async {
        let bus = EventBus()
        let recall = RecallEngine(continuity: ContinuityEngine(eventBus: bus),
                                  memory: MemoryEngine(eventBus: bus, scorer: ImportanceScorer(threshold: 0)))
        let bundle = await recall.recall()
        XCTAssertNil(bundle.objective)
    }

    // MARK: - KnowledgeEngine (§82)

    func testLinkAndNeighbors() async {
        let knowledge = KnowledgeEngine()
        let project = KnowledgeNode(kind: .project, label: "Essays")
        let objective = KnowledgeNode(kind: .objective, label: "Draft intro")
        await knowledge.add(project)
        await knowledge.add(objective)
        await knowledge.link(from: project.id, to: objective.id, relation: "contains")

        let neighbors = await knowledge.neighbors(of: project.id)
        XCTAssertEqual(neighbors.map(\.id), [objective.id])
    }

    func testSummarizeCountsRelations() async {
        let knowledge = KnowledgeEngine()
        let project = KnowledgeNode(kind: .project, label: "Startup")
        await knowledge.add(project)
        await knowledge.add(KnowledgeNode(kind: .objective, label: "o1"))
        let o2 = KnowledgeNode(kind: .objective, label: "o2")
        await knowledge.add(o2)
        // link project to two objectives
        let all = await knowledge.allNodes()
        for node in all where node.kind == .objective {
            await knowledge.link(from: project.id, to: node.id, relation: "contains")
        }
        let summary = await knowledge.summarize(project.id)
        XCTAssertTrue(summary.contains("Startup"))
        XCTAssertTrue(summary.contains("2"))
    }
}
