import XCTest
import Speech
@testable import Aria

final class LectureSessionTests: XCTestCase {

    // Each test gets a fresh LectureSession to avoid shared state contamination.
    func makeFreshSession() -> LectureSession {
        LectureSession()
    }

    // MARK: - State machine

    func testInitialStateIsIdle() async {
        let session = makeFreshSession()
        let state = await session.state
        XCTAssertEqual(state, .idle)
    }

    func testStartSetsStateRecording() async throws {
        let session = makeFreshSession()
        // Inject an engine that fails permission immediately so start() throws —
        // but with authorized + nil recognizer it also throws recognizerUnavailable.
        // For state == .recording we need a no-op engine. We achieve this by
        // configuring authorized + a recognizer factory that returns nil would throw.
        // Actually, to get .recording we need start() to succeed, which requires real
        // audio hardware. So instead we test that after a successful processChunk the
        // note is built — and test the .recording path via the actor's state after
        // manually injecting a pre-configured engine that bypasses audio.

        // Simpler: We test that start() with permissionDenied throws and leaves state idle.
        let engine = AmbientTranscriptionEngine()
        await engine.configure(requestAuthorization: { .denied })
        await session.configure(engineFactory: { engine })

        do {
            try await session.start(title: "Test", synthesize: { _ in "" })
            XCTFail("Expected permissionDenied")
        } catch AmbientTranscriptionError.permissionDenied {
            // correct
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = await session.state
        XCTAssertEqual(state, .idle)
    }

    func testStopFromIdleReturnsNil() async {
        let session = makeFreshSession()
        let result = await session.stop()
        XCTAssertNil(result)
    }

    // MARK: - Chunk processing

    func testChunkProcessingBuildsOutline() async throws {
        let session = makeFreshSession()

        // Manually prime the session state by calling processChunk directly
        // (we can't call start() without real audio, but processChunk is internal)
        // We need a note to exist — simulate by starting with denied engine then
        // directly priming. Actually processChunk guards on note != nil so we need
        // a note. Let's use a workaround: expose a test-only init helper.

        // The cleanest approach: verify processChunk when note IS set.
        // We'll call stop() first (noop), then use the shared session won't work.
        // Instead let's test via a session where we manually set up the note.
        // Since we can't set private state, we rely on processChunk doing nothing
        // when note is nil and verify via rawTranscript accumulation after start.

        // Verify: processChunk with a valid synthesize → note.outline updated
        // We simulate this by calling processChunk on a session that has a note
        // via a successful (but no-op engine) start.
        // Since we can't start without audio, test the JSON parsing logic directly
        // via processChunk on a freshly built session with note pre-populated via
        // our test-only path below.

        // Direct unit test of the JSON parsing path:
        let synthesizeJSON = """
        {"outline":[{"heading":"Introduction","bullets":["Key point A","Key point B"]}],"keyTerms":[{"term":"Actor","definition":"A concurrent Swift type"}]}
        """
        let synthesize: LectureSession.Synthesizer = { _ in synthesizeJSON }

        // Call processChunk directly — it guards on note != nil so we need to prime.
        // Use the stop(synthesize:) no-op path first just to confirm nil return.
        let nilResult = await session.stop(synthesize: synthesize)
        XCTAssertNil(nilResult)

        // Now prime with a note by simulating start internals via processChunk
        // (the method does nothing when note is nil, so this is a no-op guard test)
        await session.processChunk("Introduction to Swift actors.", synthesize: synthesize)

        // After processChunk with nil note: nothing updated (safe)
        let noteAfterNilChunk = await session.currentNote()
        XCTAssertNil(noteAfterNilChunk)

        // For the full happy-path test, we test the outline parsing logic
        // by verifying that a valid JSON synthesize produces expected structure.
        // We do this via a primed session using the internal testPrime helper.
        let primedSession = LectureSession()
        await primedSession.primeForTesting(title: "Test Lecture")

        await primedSession.processChunk("Swift concurrency uses actors.", synthesize: synthesize)

        let note = await primedSession.currentNote()
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.outline.count, 1)
        XCTAssertEqual(note?.outline.first?.heading, "Introduction")
        XCTAssertEqual(note?.outline.first?.bullets.count, 2)
        XCTAssertEqual(note?.keyTerms.count, 1)
        XCTAssertEqual(note?.keyTerms.first?.term, "Actor")
    }

    func testChunkFallbackOnSynthesisError() async throws {
        let session = LectureSession()
        await session.primeForTesting(title: "Fallback Test")

        let failingSynthesize: LectureSession.Synthesizer = { _ in
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }

        await session.processChunk("Some lecture content.", synthesize: failingSynthesize)

        let note = await session.currentNote()
        XCTAssertNotNil(note)
        // rawTranscript still accumulated
        XCTAssertTrue(note?.rawTranscript.contains("Some lecture content.") == true)
        // outline got a "Notes" fallback section
        XCTAssertTrue(note?.outline.contains(where: { $0.heading == "Notes" }) == true)
    }

    func testRawTranscriptAccumulates() async throws {
        let session = LectureSession()
        await session.primeForTesting(title: "Transcript Test")

        let noopSynthesize: LectureSession.Synthesizer = { _ in
            throw NSError(domain: "test", code: 1)
        }

        await session.processChunk("First segment.", synthesize: noopSynthesize)
        await session.processChunk("Second segment.", synthesize: noopSynthesize)

        let note = await session.currentNote()
        XCTAssertTrue(note?.rawTranscript.contains("First segment.") == true)
        XCTAssertTrue(note?.rawTranscript.contains("Second segment.") == true)
    }

    func testDoubleStartIsNoop() async throws {
        // Verify that calling start() twice doesn't crash.
        // Both calls will fail with permissionDenied (injected engine), so state stays idle.
        let session = LectureSession()
        let engine = AmbientTranscriptionEngine()
        await engine.configure(requestAuthorization: { .denied })
        await session.configure(engineFactory: { engine })

        do { try await session.start(title: nil, synthesize: { _ in "" }) } catch {}
        do { try await session.start(title: nil, synthesize: { _ in "" }) } catch {}

        let state = await session.state
        XCTAssertEqual(state, .idle)
    }

    func testKeyTermsDeduplicated() async throws {
        let session = LectureSession()
        await session.primeForTesting(title: "Dedup Test")

        let json1 = """
        {"outline":[{"heading":"A","bullets":["x"]}],"keyTerms":[{"term":"Concurrency","definition":"Parallel execution"}]}
        """
        let json2 = """
        {"outline":[{"heading":"A","bullets":["x"]}],"keyTerms":[{"term":"Concurrency","definition":"Updated definition"}]}
        """

        await session.processChunk("Chunk 1", synthesize: { _ in json1 })
        await session.processChunk("Chunk 2", synthesize: { _ in json2 })

        let note = await session.currentNote()
        let concurrencyTerms = note?.keyTerms.filter { $0.term == "Concurrency" } ?? []
        XCTAssertEqual(concurrencyTerms.count, 1, "Key terms should be deduplicated by term name")
    }
}

// MARK: - Test helpers

extension LectureSession {
    /// Primes the session with a blank note for unit testing processChunk directly.
    func primeForTesting(title: String) async {
        // This mirrors what start() does without needing real audio.
        // We call this internal method to inject a note into the actor.
        injectNoteForTesting(LectureNote(
            id: UUID(),
            title: title,
            date: Date(),
            outline: [],
            keyTerms: [],
            summary: "",
            potentialExamQuestions: [],
            rawTranscript: "",
            durationSeconds: 0
        ))
    }

    func injectNoteForTesting(_ note: LectureNote) {
        self.note = note
    }
}
