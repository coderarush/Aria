import XCTest
@testable import Aria

final class Part5WorkflowArtifactTests: XCTestCase {

    // MARK: - WorkflowEngine (§96)

    func testExtractCreatesCandidateWithParameters() async {
        let engine = WorkflowEngine()
        let workflow = await engine.extract(name: "send", steps: [
            PlanStep(tool: "gmail", parameters: ["to": "$recipient"]),
        ])
        XCTAssertEqual(workflow.state, .candidate)
        XCTAssertTrue(workflow.parameters.contains("recipient"))
    }

    func testReuseSubstitutesParameters() async {
        let engine = WorkflowEngine()
        let workflow = await engine.extract(name: "send", steps: [
            PlanStep(tool: "gmail", parameters: ["to": "$recipient"]),
        ])
        let steps = await engine.reuse(workflow.id, parameters: ["recipient": "a@b.com"])
        XCTAssertEqual(steps.first?.parameters["to"], "a@b.com")
    }

    func testStateTransitions() async {
        let engine = WorkflowEngine()
        let workflow = await engine.extract(name: "w", steps: [])
        await engine.approve(workflow.id)
        await engine.activate(workflow.id)
        let active = await engine.get(workflow.id)
        XCTAssertEqual(active?.state, .active)
        await engine.retire(workflow.id)
        let retired = await engine.get(workflow.id)
        XCTAssertEqual(retired?.state, .retired)
    }

    func testComposeConcatenatesSteps() async {
        let engine = WorkflowEngine()
        let a = await engine.extract(name: "a", steps: [PlanStep(tool: "1")])
        let b = await engine.extract(name: "b", steps: [PlanStep(tool: "2"), PlanStep(tool: "3")])
        let composed = await engine.compose([a.id, b.id])
        XCTAssertEqual(composed.count, 3)
    }

    // MARK: - ArtifactEngine (§97)

    func testCreateThenUpdateVersions() async {
        let engine = ArtifactEngine()
        let artifact = await engine.create(kind: .document, content: "v1 text")
        await engine.update(artifact.id, content: "v2 text")
        let current = await engine.get(artifact.id)?.current
        XCTAssertEqual(current?.version, 2)
        XCTAssertEqual(current?.content, "v2 text")
    }

    func testRestoreBringsBackOldContent() async {
        let engine = ArtifactEngine()
        let artifact = await engine.create(kind: .code, content: "a")
        await engine.update(artifact.id, content: "b")
        await engine.restore(artifact.id, to: 1)
        let current = await engine.get(artifact.id)?.current
        XCTAssertEqual(current?.content, "a")
    }

    func testCompareDetectsDifference() async {
        let engine = ArtifactEngine()
        let artifact = await engine.create(kind: .plan, content: "x")
        await engine.update(artifact.id, content: "y")
        let equal = await engine.compare(artifact.id, 1, 2)
        XCTAssertFalse(equal)
    }
}
