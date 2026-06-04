import XCTest
@testable import Aria

final class LongTermMemoryTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("aria-mem-\(UUID()).json")
    }

    func testRememberPersistsAndDedupes() async {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let m = LongTermMemory(fileURL: url)
        let added1 = await m.remember("I prefer the metric system", kind: "preference")
        let added2 = await m.remember("i prefer the metric system")   // dup (normalized)
        XCTAssertTrue(added1)
        XCTAssertFalse(added2)
        let count = await m.all().count
        XCTAssertEqual(count, 1)

        // Reloads from disk in a fresh instance.
        let m2 = LongTermMemory(fileURL: url)
        let reloaded = await m2.all()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.kind, "preference")
    }

    func testRecallRanksByRelevance() {
        let now = Date()
        let facts = [
            MemoryFact(text: "I have a dog named Rex", createdAt: now),
            MemoryFact(text: "I work as a software engineer", createdAt: now),
            MemoryFact(text: "My favorite food is sushi", createdAt: now),
        ]
        let ranked = LongTermMemory.rank(facts, query: "what's my dog called", now: now)
        XCTAssertEqual(ranked.first?.text, "I have a dog named Rex")
    }

    func testRecallReturnsEmptyForUnrelated() {
        let now = Date()
        let facts = [MemoryFact(text: "I like hiking", createdAt: now)]
        XCTAssertTrue(LongTermMemory.rank(facts, query: "quantum chromodynamics", now: now).isEmpty)
    }
}
