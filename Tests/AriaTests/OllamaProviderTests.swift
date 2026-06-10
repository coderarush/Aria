import XCTest
@testable import Aria

final class OllamaProviderTests: XCTestCase {

    func testDefaultsToQwen3() {
        let p = OllamaProvider()
        XCTAssertEqual(p.model, "qwen3:8b")
        XCTAssertEqual(p.id, "local-ollama")
    }

    func testEmptyModelNameFallsBackToDefault() {
        let p = OllamaProvider(model: "  ")
        XCTAssertEqual(p.model, "qwen3:8b")
    }

    func testCustomModelRespected() {
        let p = OllamaProvider(model: "llama3.1:8b")
        XCTAssertEqual(p.model, "llama3.1:8b")
    }

    func testUnavailableWhenProbeFails() async {
        let p = OllamaProvider(probe: { false })
        let available = await p.isAvailable()
        XCTAssertFalse(available)
    }

    func testAvailableWhenProbeSucceeds() async {
        let p = OllamaProvider(probe: { true })
        let available = await p.isAvailable()
        XCTAssertTrue(available)
    }

    func testGeminiProviderConformsAndIsAlwaysWorthTrying() async {
        let p = GeminiProvider()
        let available = await p.isAvailable()
        XCTAssertTrue(available)
        XCTAssertEqual(p.id, "cloud-gemini")
    }

    /// Live probe against a real local Ollama server. Gated: run with
    ///   ARIA_LOCAL_LIVE=1 ARIA_LOCAL_MODEL=qwen3.5:4b swift test --filter testLiveLocalGeneration
    func testLiveLocalGeneration() async throws {
        guard ProcessInfo.processInfo.environment["ARIA_LOCAL_LIVE"] == "1" else {
            throw XCTSkip("set ARIA_LOCAL_LIVE=1 to run against a live Ollama server")
        }
        let model = ProcessInfo.processInfo.environment["ARIA_LOCAL_MODEL"] ?? OllamaProvider.defaultModel
        let p = OllamaProvider(model: model)
        let alive = await p.isAvailable()
        XCTAssertTrue(alive, "Ollama server not reachable")
        let out = try await p.generateText(prompt: "Reply with exactly the word: ready", temperature: 0)
        XCTAssertFalse(out.isEmpty)
    }
}
