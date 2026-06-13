import XCTest
@testable import Aria

/// Tests the PURE fusion core of unified recall — `RecallRanker.fuse` — over
/// in-memory per-source hit lists. No real stores, no filesystem: the merge/rank
/// is the testable heart, and it's a deterministic sync function.
final class UnifiedRecallTests: XCTestCase {

    private func hit(_ source: RecallHit.Source, _ title: String, score: Double = 1.0) -> RecallHit {
        RecallHit(source: source, title: title, snippet: "snippet for \(title)", score: score)
    }

    // MARK: Interleaving

    /// Hits from multiple sources interleave by fused RRF score: each source's
    /// rank-0 hit ties at the top, then rank-1, etc. — so the merged list weaves
    /// the sources together rather than concatenating them.
    func testSourcesInterleaveByFusedRank() {
        let conv = [hit(.conversation, "C0"), hit(.conversation, "C1")]
        let work = [hit(.work, "W0"), hit(.work, "W1")]

        let fused = RecallRanker.fuse([conv, work])
        let titles = fused.map(\.title)

        // Both rank-0 hits come before either rank-1 hit (equal RRF at each rank,
        // source order breaks the tie: conversation before work).
        XCTAssertEqual(titles, ["C0", "W0", "C1", "W1"])
    }

    // MARK: Strong-in-one beats weak-in-others

    /// A hit that ranks #1 in its source outranks hits that only ever appear far
    /// down other sources — regardless of the sources' raw score scales.
    func testStrongHitOutranksWeakHitsInOtherSources() {
        // Document source: huge raw scores but our target is its TOP hit.
        let docs = [hit(.document, "TopDoc", score: 999)]
        // Context source: a long list; the relevant fact is buried at the bottom.
        let context = (0..<5).map { hit(.context, "Ctx\($0)", score: 0.01) }

        let fused = RecallRanker.fuse([docs, context])

        // The doc (rank 0 -> 1/60) beats every context hit from rank 1 down.
        XCTAssertEqual(fused.first?.title, "TopDoc")
        // And a rank-0 context hit (Ctx0, also 1/60) ties the doc but loses the
        // source tie-break (document declared before context), so doc still leads.
        XCTAssertEqual(fused.prefix(2).map(\.title), ["TopDoc", "Ctx0"])
    }

    /// Agreement across sources wins: a hit present (even mid-rank) in two sources
    /// accumulates more RRF than a hit that tops only one source.
    func testCrossSourceAgreementAccumulates() {
        // Same id (source+title+snippet) appearing in two source lists fuses.
        let shared = RecallHit(source: .work, title: "Shared", snippet: "same", score: 1)
        let listA = [hit(.work, "A0"), shared]          // shared at rank 1 -> 1/61
        let listB = [shared]                            // shared at rank 0 -> 1/60
        // shared total = 1/61 + 1/60 ≈ 0.0330 ; A0 = 1/60 ≈ 0.0167
        let fused = RecallRanker.fuse([listA, listB])
        XCTAssertEqual(fused.first?.title, "Shared")
        // Dedup: "Shared" appears once despite being in two lists.
        XCTAssertEqual(fused.filter { $0.title == "Shared" }.count, 1)
    }

    // MARK: Empty sources

    /// Empty per-source lists are skipped and don't perturb ordering or counts.
    func testEmptySourcesAreSkipped() {
        let conv = [hit(.conversation, "C0")]
        let fused = RecallRanker.fuse([[], conv, [], []])
        XCTAssertEqual(fused.map(\.title), ["C0"])
    }

    func testAllEmptyReturnsEmpty() {
        XCTAssertTrue(RecallRanker.fuse([[], [], []]).isEmpty)
        XCTAssertTrue(RecallRanker.fuse([]).isEmpty)
    }

    // MARK: Limit

    func testLimitRespected() {
        let conv = (0..<10).map { hit(.conversation, "C\($0)") }
        let fused = RecallRanker.fuse([conv], limit: 3)
        XCTAssertEqual(fused.count, 3)
        XCTAssertEqual(fused.map(\.title), ["C0", "C1", "C2"])
    }

    func testNonPositiveLimitReturnsAll() {
        let conv = (0..<4).map { hit(.conversation, "C\($0)") }
        XCTAssertEqual(RecallRanker.fuse([conv], limit: 0).count, 4)
        XCTAssertEqual(RecallRanker.fuse([conv], limit: nil).count, 4)
    }

    // MARK: Determinism

    /// Same input -> byte-identical ordering every time, including tie-breaks.
    func testDeterministicOrdering() {
        let conv = [hit(.conversation, "C0"), hit(.conversation, "C1")]
        let docs = [hit(.document, "D0"), hit(.document, "D1")]
        let context = [hit(.context, "X0")]
        let work = [hit(.work, "W0")]

        let first = RecallRanker.fuse([conv, docs, context, work]).map(\.title)
        for _ in 0..<20 {
            XCTAssertEqual(RecallRanker.fuse([conv, docs, context, work]).map(\.title), first)
        }
        // Expected weave: all four rank-0 hits (source order), then the rank-1s.
        XCTAssertEqual(first, ["C0", "D0", "X0", "W0", "C1", "D1"])
    }

    // MARK: Source tag formatting (the tool's contract)

    func testSourceTags() {
        XCTAssertEqual(RecallHit.Source.conversation.tag, "[conversation]")
        XCTAssertEqual(RecallHit.Source.document.tag, "[doc]")
        XCTAssertEqual(RecallHit.Source.context.tag, "[context]")
        XCTAssertEqual(RecallHit.Source.work.tag, "[work]")
    }
}
