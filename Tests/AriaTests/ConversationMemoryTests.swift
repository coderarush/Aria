import XCTest
@testable import Aria

final class ConversationMemoryTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-mem-\(UUID().uuidString).json")
    }

    func testAppendAndContextWindow() async {
        let memory = ConversationMemory(fileURL: tempURL())
        for i in 0..<10 {
            await memory.append(ConversationTurn(
                transcript: "q\(i)", responseMessage: "a\(i)", responseType: .answer))
        }
        let context = await memory.recentContext()
        XCTAssertEqual(context.count, 6)
        XCTAssertEqual(context.first?.transcript, "q4")
        XCTAssertEqual(context.last?.transcript, "q9")
    }

    func testMaxStoredCap() async {
        let memory = ConversationMemory(fileURL: tempURL())
        for i in 0..<60 {
            await memory.append(ConversationTurn(
                transcript: "q\(i)", responseMessage: "a\(i)", responseType: .answer))
        }
        let all = await memory.turns
        XCTAssertEqual(all.count, 50)
        XCTAssertEqual(all.first?.transcript, "q10")
    }

    func testPersistenceRoundTrip() async {
        let url = tempURL()
        let first = ConversationMemory(fileURL: url)
        await first.append(ConversationTurn(
            transcript: "remember this", responseMessage: "ok", responseType: .answer))

        let reloaded = ConversationMemory(fileURL: url)
        let turns = await reloaded.turns
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.transcript, "remember this")
    }

    func testSearch() async {
        let memory = ConversationMemory(fileURL: tempURL())
        await memory.append(ConversationTurn(
            transcript: "what's the weather", responseMessage: "sunny", responseType: .answer))
        await memory.append(ConversationTurn(
            transcript: "open safari", responseMessage: "done", responseType: .answer))
        let hits = await memory.search("weather")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.responseMessage, "sunny")
    }
}
