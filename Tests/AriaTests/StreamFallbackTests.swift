import XCTest
@testable import Aria

private final class PrimaryOutcomeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [(ok: Bool, latency: TimeInterval)] = []

    func record(ok: Bool, latency: TimeInterval) {
        lock.lock()
        outcomes.append((ok, latency))
        lock.unlock()
    }

    var values: [(ok: Bool, latency: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        return outcomes
    }
}

final class StreamFallbackTests: XCTestCase {

    private func stream(_ events: [StreamEvent], thenError: Bool = false,
                        errorBeforeAny: Bool = false) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { c in
            if errorBeforeAny {
                c.finish(throwing: GeminiClient.GeminiError.emptyResponse)
                return
            }
            for e in events { c.yield(e) }
            if thenError { c.finish(throwing: GeminiClient.GeminiError.emptyResponse) }
            else { c.finish() }
        }
    }

    private func collect(_ s: AsyncThrowingStream<StreamEvent, Error>) async throws -> [StreamEvent] {
        var out: [StreamEvent] = []
        for try await e in s { out.append(e) }
        return out
    }

    func testPrimarySuccessNeverTouchesFallback() async throws {
        var fellBack = false
        let s = GeminiClient.streamWithFallback(
            primary: stream([.text("local ")]),
            fallback: { fellBack = true; return self.stream([.text("cloud")]) })
        let events = try await collect(s)
        XCTAssertEqual(events, [.text("local ")])
        XCTAssertFalse(fellBack)
    }

    func testPrimaryFailingBeforeAnyOutputFallsBack() async throws {
        let s = GeminiClient.streamWithFallback(
            primary: stream([], errorBeforeAny: true),
            fallback: { self.stream([.text("cloud answer")]) })
        let events = try await collect(s)
        XCTAssertEqual(events, [.text("cloud answer")])
    }

    func testPrimaryFailureReportsOneOutcomeBeforeFallback() async throws {
        let recorder = PrimaryOutcomeRecorder()
        let s = GeminiClient.streamWithFallback(
            primary: stream([], errorBeforeAny: true),
            fallback: { self.stream([.text("cloud answer")]) },
            onPrimaryOutcome: { ok, latency in recorder.record(ok: ok, latency: latency) })

        let events = try await collect(s)
        XCTAssertEqual(events, [.text("cloud answer")])
        XCTAssertEqual(recorder.values.count, 1)
        XCTAssertFalse(recorder.values[0].ok)
        XCTAssertGreaterThanOrEqual(recorder.values[0].latency, 0)
    }

    func testPrimaryFirstOutputReportsOneSuccessfulOutcome() async throws {
        let recorder = PrimaryOutcomeRecorder()
        let s = GeminiClient.streamWithFallback(
            primary: stream([.text("local")]),
            fallback: { self.stream([.text("cloud")]) },
            onPrimaryOutcome: { ok, latency in recorder.record(ok: ok, latency: latency) })

        let events = try await collect(s)
        XCTAssertEqual(events, [.text("local")])
        XCTAssertEqual(recorder.values.count, 1)
        XCTAssertTrue(recorder.values[0].ok)
    }

    func testSlowPrimaryFirstTokenFallsBackOnTimeout() async throws {
        let slow = AsyncThrowingStream<StreamEvent, Error> { c in
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)   // way past budget
                c.yield(.text("too late"))
                c.finish()
            }
        }
        let s = GeminiClient.streamWithFallback(
            primary: slow,
            fallback: { self.stream([.text("cloud rescued")]) },
            firstTokenTimeout: 0.2)
        let events = try await collect(s)
        XCTAssertEqual(events, [.text("cloud rescued")])
    }

    func testFastPrimaryUnaffectedByTimeout() async throws {
        let s = GeminiClient.streamWithFallback(
            primary: stream([.text("quick local")]),
            fallback: { self.stream([.text("cloud")]) },
            firstTokenTimeout: 5)
        let events = try await collect(s)
        XCTAssertEqual(events, [.text("quick local")])
    }

    func testPrimaryFailingMidStreamPropagatesError() async {
        // Once the user has heard local output, silently restarting on cloud
        // would double-speak — propagate instead.
        let s = GeminiClient.streamWithFallback(
            primary: stream([.text("partial")], thenError: true),
            fallback: { self.stream([.text("cloud")]) })
        do {
            _ = try await collect(s)
            XCTFail("expected error")
        } catch {}
    }
}
