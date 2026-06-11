import XCTest
@testable import Aria

/// V11 P1 — local-first setup: hardware profiling → model recommendation →
/// installation via Ollama's pull API → health.
final class LocalModelSetupTests: XCTestCase {

    // MARK: recommendation tiers (constitution: 8GB→4B, 16GB→8B, 24GB+→14B)

    func testRecommendationTiers() {
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 8), "qwen3:4b")
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 16), "qwen3:8b")
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 18), "qwen3:8b")
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 24), "qwen3:14b")
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 64), "qwen3:14b")
    }

    func testLowDiskDowngradesRecommendation() {
        // 14B needs ~10GB free; with 6GB free a 24GB machine still gets 8B.
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 32, freeDiskGB: 6), "qwen3:8b")
        // Critically low disk → smallest model.
        XCTAssertEqual(HardwareProfiler.recommendedModel(ramGB: 32, freeDiskGB: 3), "qwen3:4b")
    }

    func testProfileReadsRealHardware() {
        let profile = HardwareProfiler.profile()
        XCTAssertGreaterThan(profile.ramGB, 0)
        XCTAssertFalse(profile.chip.isEmpty)
        XCTAssertFalse(profile.recommendedModel.isEmpty)
    }

    // MARK: pull progress parsing (Ollama NDJSON)

    func testParsesPullProgressLines() {
        let line = #"{"status":"pulling 9f4ae0aff61e","completed":104857600,"total":1048576000}"#
        let p = ModelInstaller.progress(fromPullLine: Data(line.utf8))
        XCTAssertEqual(p?.fraction ?? 0, 0.1, accuracy: 0.001)
        XCTAssertFalse(p?.done ?? true)
    }

    func testParsesPullSuccessLine() {
        let line = #"{"status":"success"}"#
        let p = ModelInstaller.progress(fromPullLine: Data(line.utf8))
        XCTAssertTrue(p?.done ?? false)
    }

    func testParsesPullErrorLine() {
        let line = #"{"error":"pull model manifest: file does not exist"}"#
        let p = ModelInstaller.progress(fromPullLine: Data(line.utf8))
        XCTAssertNotNil(p?.error)
    }

    func testIgnoresGarbageLines() {
        XCTAssertNil(ModelInstaller.progress(fromPullLine: Data("not json".utf8)))
    }

    // MARK: setup status decisions

    func testStatusOllamaMissing() {
        let s = ModelInstaller.status(binaryPresent: false, serverAlive: false,
                                      installedModels: [], wanted: "qwen3:8b")
        XCTAssertEqual(s, .ollamaMissing)
    }

    func testStatusServerDown() {
        let s = ModelInstaller.status(binaryPresent: true, serverAlive: false,
                                      installedModels: [], wanted: "qwen3:8b")
        XCTAssertEqual(s, .serverDown)
    }

    func testStatusModelMissing() {
        let s = ModelInstaller.status(binaryPresent: true, serverAlive: true,
                                      installedModels: ["llama3:8b"], wanted: "qwen3:8b")
        XCTAssertEqual(s, .modelMissing)
    }

    func testStatusReadyMatchesTagVariants() {
        // Ollama reports "qwen3:8b" exactly; also accept name-only prefix match.
        let s = ModelInstaller.status(binaryPresent: true, serverAlive: true,
                                      installedModels: ["qwen3:8b"], wanted: "qwen3:8b")
        XCTAssertEqual(s, .ready)
    }

    // MARK: health

    func testHealthTracksOutcomes() async {
        let health = LocalModelHealth()
        await health.record(ok: true, latency: 1.2)
        await health.record(ok: false, latency: 0)
        await health.record(ok: true, latency: 0.8)
        let snap = await health.snapshot()
        XCTAssertEqual(snap.successes, 2)
        XCTAssertEqual(snap.failures, 1)
        XCTAssertEqual(snap.lastLatency ?? 0, 0.8, accuracy: 0.001)
    }
}
