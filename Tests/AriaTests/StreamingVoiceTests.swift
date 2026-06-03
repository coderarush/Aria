import XCTest
@testable import Aria

@MainActor
final class StreamingVoiceTests: XCTestCase {
    func testQueuesAndReportsSpeakingState() {
        let spoken = Spy()
        let sv = StreamingVoice(speakChunk: { spoken.calls.append($0) },
                                stopAll: { spoken.stopped = true })
        sv.enqueue("One.")
        sv.enqueue("Two.")
        XCTAssertEqual(spoken.calls, ["One."])     // first speaks immediately
        sv.chunkDidFinish()                          // simulate first finished
        XCTAssertEqual(spoken.calls, ["One.", "Two."])
        XCTAssertTrue(sv.isSpeaking)
        sv.chunkDidFinish()
        XCTAssertFalse(sv.isSpeaking)               // queue drained
    }

    func testStopClearsQueue() {
        let spoken = Spy()
        let sv = StreamingVoice(speakChunk: { spoken.calls.append($0) },
                                stopAll: { spoken.stopped = true })
        sv.enqueue("One."); sv.enqueue("Two.")
        sv.stop()
        XCTAssertTrue(spoken.stopped)
        XCTAssertFalse(sv.isSpeaking)
        sv.chunkDidFinish()                          // late callback after stop = no-op
        XCTAssertEqual(spoken.calls, ["One."])       // Two. never spoken
    }

    final class Spy { var calls: [String] = []; var stopped = false }
}
