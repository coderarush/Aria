import XCTest
@testable import Aria

final class ArtifactGraphTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)
    private func a(_ kind: Artifact.Kind, _ id: String, _ label: String, project: String? = nil, _ dt: TimeInterval) -> Artifact {
        Artifact(kind: kind, id: id, label: label, project: project, date: t.addingTimeInterval(dt))
    }

    func testAllMergesDedupesSortedNewestFirst() async {
        let g = ArtifactGraph(providers: [
            { [self.a(.doc, "d1", "spec", 10), self.a(.doc, "d1", "spec", 10)] },  // dup
            { [self.a(.commit, "c1", "feat", 50)] }
        ])
        let all = await g.all()
        XCTAssertEqual(all.count, 2)                       // deduped
        XCTAssertEqual(all.first?.id, "c1")               // newest first
    }

    func testLatestOverallAndByKind() async {
        let g = ArtifactGraph(providers: [{
            [self.a(.doc, "d1", "old doc", 10), self.a(.commit, "c1", "commit", 90),
             self.a(.doc, "d2", "new doc", 80)]
        }])
        let latest = await g.latest()
        XCTAssertEqual(latest?.id, "c1")
        let latestDoc = await g.latest(kind: .doc)
        XCTAssertEqual(latestDoc?.id, "d2")
    }

    func testRelatedByProject() async {
        let g = ArtifactGraph(providers: [{
            [self.a(.doc, "d1", "aria doc", project: "Aria", 10),
             self.a(.commit, "c1", "aria commit", project: "Aria", 5000),
             self.a(.doc, "d2", "other", project: "Other", 11)]
        }])
        let anchor = self.a(.doc, "d1", "aria doc", project: "Aria", 10)
        let related = await g.related(to: anchor, within: 0.5)   // tight window → project drives it
        XCTAssertTrue(related.contains { $0.id == "c1" })
        XCTAssertFalse(related.contains { $0.id == "d2" })
    }

    func testRelatedByTimeWindow() async {
        let g = ArtifactGraph(providers: [{
            [self.a(.commit, "c1", "near", 100), self.a(.commit, "c2", "far", 999999)]
        }])
        let anchor = self.a(.doc, "anchor", "anchor", 90)
        let related = await g.related(to: anchor, within: 60)
        XCTAssertEqual(related.map(\.id), ["c1"])
    }

    func testFindByLabel() async {
        let g = ArtifactGraph(providers: [{
            [self.a(.doc, "d1", "Launch deck", 10), self.a(.doc, "d2", "budget", 20)]
        }])
        let hits = await g.find("launch")
        XCTAssertEqual(hits.map(\.id), ["d1"])
        let empty = await g.find("")
        XCTAssertTrue(empty.isEmpty)
    }

    func testEmpty() async {
        let g = ArtifactGraph(providers: [])
        let all = await g.all()
        XCTAssertTrue(all.isEmpty)
        let latest = await g.latest()
        XCTAssertNil(latest)
    }
}
