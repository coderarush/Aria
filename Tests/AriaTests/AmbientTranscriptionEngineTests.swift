import XCTest
import Speech
@testable import Aria

final class AmbientTranscriptionEngineTests: XCTestCase {

    // MARK: State machine — no hardware needed

    func testInitialStateIsIdle() async {
        let engine = AmbientTranscriptionEngine()
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testPermissionDeniedThrows() async {
        let engine = AmbientTranscriptionEngine()
        // Inject a denied authorization response via the actor-isolated configure() helper
        await engine.configure(
            requestAuthorization: { .denied },
            recognizerFactory: { locale in SFSpeechRecognizer(locale: locale) }
        )

        do {
            try await engine.start(onChunk: { _, _ in })
            XCTFail("Expected permissionDenied error")
        } catch AmbientTranscriptionError.permissionDenied {
            // correct
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // State must remain idle after the throw
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testRecognizerUnavailableThrows() async {
        let engine = AmbientTranscriptionEngine()
        // Permission granted, but factory returns nil (e.g. unsupported locale)
        await engine.configure(
            requestAuthorization: { .authorized },
            recognizerFactory: { _ in nil }
        )

        do {
            try await engine.start(onChunk: { _, _ in })
            XCTFail("Expected recognizerUnavailable error")
        } catch AmbientTranscriptionError.recognizerUnavailable {
            // correct
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testStopFromIdleIsNoop() async {
        let engine = AmbientTranscriptionEngine()
        // stop() on an idle engine must not crash and must leave state as idle
        await engine.stop()
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testPauseFromIdleIsNoop() async {
        let engine = AmbientTranscriptionEngine()
        // pause() on an idle engine must not crash and must leave state as idle
        await engine.pause()
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testCurrentBufferInitiallyEmpty() async {
        let engine = AmbientTranscriptionEngine()
        let buffer = await engine.currentBuffer()
        XCTAssertEqual(buffer, "")
    }
}
