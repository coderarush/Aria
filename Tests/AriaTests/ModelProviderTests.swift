import XCTest
@testable import Aria

final class DeterministicProviderTests: XCTestCase {

    func testReturnsScriptedResponseForMatchingPrompt() async throws {
        let provider = DeterministicProvider(script: [
            "weather": "It's 72 and sunny.",
            "joke": "Two atoms walk into a bar."
        ], fallback: "Demo response.")
        let out = try await provider.generateText(prompt: "what's the weather like", temperature: 0.3)
        XCTAssertEqual(out, "It's 72 and sunny.")
    }

    func testFallsBackWhenNothingMatches() async throws {
        let provider = DeterministicProvider(script: [:], fallback: "Demo response.")
        let out = try await provider.generateText(prompt: "anything", temperature: 0.3)
        XCTAssertEqual(out, "Demo response.")
    }

    func testRecordsTranscriptInOrder() async throws {
        let provider = DeterministicProvider(script: [:], fallback: "ok")
        _ = try await provider.generateText(prompt: "first", temperature: 0)
        _ = try await provider.generateText(prompt: "second", temperature: 0)
        let transcript = await provider.transcript()
        XCTAssertEqual(transcript, ["first", "second"])
    }

    func testIsAlwaysAvailable() async {
        let provider = DeterministicProvider(script: [:], fallback: "ok")
        let available = await provider.isAvailable()
        XCTAssertTrue(available)
        XCTAssertEqual(provider.id, "deterministic")
    }
}
