import XCTest
@testable import Aria

final class ArtifactToolTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func graph() -> ArtifactGraph {
        ArtifactGraph(providers: [{ [
            Artifact(kind: .doc, id: "d1", label: "Launch deck", project: "Aria", date: self.t),
            Artifact(kind: .session, id: "s1", label: "wrote report", project: "Aria", date: self.t.addingTimeInterval(100))
        ] }])
    }

    func testLatest() async throws {
        let r = try await ArtifactTool(graph: graph()).run(input: ["action": "latest"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.output.contains("wrote report"))   // newest
    }

    func testLatestByKind() async throws {
        let r = try await ArtifactTool(graph: graph()).run(input: ["action": "latest", "kind": "doc"])
        XCTAssertTrue(r.output.contains("Launch deck"))
    }

    func testFind() async throws {
        let r = try await ArtifactTool(graph: graph()).run(input: ["action": "find", "query": "deck"])
        XCTAssertTrue(r.output.contains("Launch deck"))
    }

    func testUnknownActionFails() async throws {
        let r = try await ArtifactTool(graph: graph()).run(input: ["action": "frob"])
        XCTAssertFalse(r.success)
    }
}
