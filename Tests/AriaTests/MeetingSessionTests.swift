import XCTest
import Speech
@testable import Aria

final class MeetingSessionTests: XCTestCase {

    func makeFreshSession() -> MeetingSession {
        MeetingSession()
    }

    // MARK: - State machine

    func testInitialStateIsIdle() async {
        let session = makeFreshSession()
        let state = await session.state
        XCTAssertEqual(state, .idle)
    }

    func testStopFromIdleReturnsNil() async {
        let session = makeFreshSession()
        let result = await session.stop()
        XCTAssertNil(result)
    }

    // MARK: - Chunk processing

    func testSegmentsAccumulatePerChunk() async throws {
        let session = MeetingSession()
        await session.primeForTesting(title: "Test Meeting")

        await session.processChunk("Hello, let's get started.")
        await session.processChunk("Sure, I agree with that proposal.")

        let note = await session.currentNote()
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.segments.count, 2)
        XCTAssertEqual(note?.segments[0].speakerLabel, "Turn 1")
        XCTAssertEqual(note?.segments[1].speakerLabel, "Turn 2")
        XCTAssertEqual(note?.segments[0].text, "Hello, let's get started.")
        XCTAssertEqual(note?.segments[1].text, "Sure, I agree with that proposal.")
    }

    func testSynthesisExtractsActionItems() async throws {
        let session = MeetingSession()
        await session.primeForTesting(title: "Action Items Meeting")

        await session.processChunk("We need to finish the report by Friday.")
        await session.processChunk("John will handle the client call.")

        let synthesizeJSON: @Sendable (String) async throws -> String = { _ in
            """
            {"actionItems":["Finish report by Friday","John handles client call"],"decisions":["Approved Q3 budget"],"openQuestions":["Timeline for phase 2?"],"summary":"The team discussed Q3 deliverables and assigned ownership of key tasks."}
            """
        }

        let finalNote = await session.stopWithSynthesize(synthesizeJSON)
        XCTAssertNotNil(finalNote)
        XCTAssertEqual(finalNote?.actionItems.count, 2)
        XCTAssertTrue(finalNote?.actionItems.contains("Finish report by Friday") == true)
        XCTAssertEqual(finalNote?.decisions.count, 1)
        XCTAssertEqual(finalNote?.openQuestions.count, 1)
        XCTAssertTrue(finalNote?.summary.contains("Q3") == true)
    }

    func testSynthesisFailureSetsDefaultSummary() async throws {
        let session = MeetingSession()
        await session.primeForTesting(title: "Fallback Meeting")

        await session.processChunk("Some discussion here.")

        let failingSynthesize: @Sendable (String) async throws -> String = { _ in
            throw NSError(domain: "test", code: 1)
        }

        let finalNote = await session.stopWithSynthesize(failingSynthesize)
        XCTAssertNotNil(finalNote)
        XCTAssertTrue(finalNote?.summary.contains("turns recorded") == true || finalNote?.summary.contains("transcript saved") == true)
    }

    func testFormattedTranscriptFormat() {
        let segments = [
            TranscriptSegment(speakerLabel: "Turn 1", text: "Hello world.", timestamp: Date()),
            TranscriptSegment(speakerLabel: "Turn 2", text: "Sounds good.", timestamp: Date())
        ]
        let notes = MeetingNotes(
            id: UUID(),
            title: "Test",
            date: Date(),
            segments: segments,
            actionItems: [],
            decisions: [],
            openQuestions: [],
            summary: "",
            durationSeconds: 0
        )

        let formatted = notes.formattedTranscript
        XCTAssertTrue(formatted.contains("[Turn 1]"), "formattedTranscript should contain [Turn 1]")
        XCTAssertTrue(formatted.contains("[Turn 2]"), "formattedTranscript should contain [Turn 2]")
        XCTAssertTrue(formatted.contains("Hello world."))
        XCTAssertTrue(formatted.contains("Sounds good."))
    }

    func testTurnLabelsIncrementSequentially() async throws {
        let session = MeetingSession()
        await session.primeForTesting(title: "Turn Labels Test")

        for i in 1...5 {
            await session.processChunk("Turn \(i) content.")
        }

        let note = await session.currentNote()
        XCTAssertEqual(note?.segments.count, 5)
        for (idx, segment) in (note?.segments ?? []).enumerated() {
            XCTAssertEqual(segment.speakerLabel, "Turn \(idx + 1)")
        }
    }

    func testStopWithNoSegmentsReturnsNil() async throws {
        let session = MeetingSession()
        await session.primeForTesting(title: "Empty Meeting")

        // Don't add any segments
        let result = await session.stopWithSynthesize({ _ in "" })
        XCTAssertNil(result, "stop() should return nil when no segments were recorded")
    }
}

// MARK: - Test helpers

extension MeetingSession {
    func primeForTesting(title: String) async {
        injectNoteForTesting(MeetingNotes(
            id: UUID(),
            title: title,
            date: Date(),
            segments: [],
            actionItems: [],
            decisions: [],
            openQuestions: [],
            summary: "",
            durationSeconds: 0
        ))
    }

    func injectNoteForTesting(_ note: MeetingNotes) {
        self.note = note
        self.setStateForTesting(.recording)
    }

    func currentNote() async -> MeetingNotes? {
        return note
    }

    /// Test-only stop that injects a synthesizer without needing real start().
    func stopWithSynthesize(_ synthesize: @escaping @Sendable (String) async throws -> String) async -> MeetingNotes? {
        self.storedSynthesize = synthesize
        return await stop()
    }
}
