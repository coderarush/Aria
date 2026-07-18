import XCTest
@testable import Aria

final class ExecutionGraphTests: XCTestCase {

    func testAddActionRegistersNode() {
        var graph = ExecutionGraph()
        let a = Domain.Action(tool: "t")
        graph.addAction(a)
        XCTAssertEqual(graph.nodes[a.id]?.tool, "t")
    }

    func testReadyNodesAreThoseWithSatisfiedDependencies() {
        var graph = ExecutionGraph()
        let a = Domain.Action(tool: "a")
        let b = Domain.Action(tool: "b")
        graph.addAction(a)
        graph.addAction(b, dependsOn: [a.id])

        XCTAssertEqual(graph.readyNodes(completed: []).map(\.id), [a.id])
        XCTAssertEqual(graph.readyNodes(completed: [a.id]).map(\.id), [b.id])
    }

    func testTopologicalOrderPlacesDependenciesFirst() throws {
        var graph = ExecutionGraph()
        let a = Domain.Action(tool: "a")
        let b = Domain.Action(tool: "b")
        let c = Domain.Action(tool: "c")
        graph.addAction(a)
        graph.addAction(b, dependsOn: [a.id])
        graph.addAction(c, dependsOn: [b.id])

        XCTAssertEqual(try graph.topologicalOrder(), [a.id, b.id, c.id])
    }

    func testCycleDetectionThrows() {
        var graph = ExecutionGraph()
        let a = Domain.Action(tool: "a")
        let b = Domain.Action(tool: "b")
        graph.addAction(a, dependsOn: [b.id])
        graph.addAction(b, dependsOn: [a.id])

        XCTAssertThrowsError(try graph.topologicalOrder())
        XCTAssertTrue(graph.hasCycle)
    }

    func testEmptyGraphHasNoCycle() {
        let graph = ExecutionGraph()
        XCTAssertFalse(graph.hasCycle)
    }
}
