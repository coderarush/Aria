import XCTest
@testable import Aria

final class CrossConnectorSynthesizerTests: XCTestCase {

    // MARK: - Helpers

    private func makeSources(
        gmail: String = "",
        gcal: String = "",
        notion: String = "",
        drive: String = "",
        slack: String = "",
        github: String = "",
        linear: String = ""
    ) -> CrossConnectorSynthesizer.Sources {
        CrossConnectorSynthesizer.Sources(
            gmail:  { _ in gmail },
            gcal:   { _ in gcal },
            notion: { _ in notion },
            drive:  { _ in drive },
            slack:  { _ in slack },
            github: { _ in github },
            linear: { _ in linear }
        )
    }

    // MARK: - Tests

    /// All 7 stubs return content; synthesize receives a prompt containing all 7 labels.
    func testGatherCombinesAllSources() async {
        let sut = CrossConnectorSynthesizer()
        let sources = makeSources(
            gmail:  "email content",
            gcal:   "calendar content",
            notion: "notion content",
            drive:  "drive content",
            slack:  "slack content",
            github: "github content",
            linear: "linear content"
        )

        var capturedPrompt = ""
        let result = await sut.gather(topic: "project alpha", sources: sources) { prompt in
            capturedPrompt = prompt
            return "Synthesized answer."
        }

        XCTAssertEqual(result, "Synthesized answer.")
        XCTAssertTrue(capturedPrompt.contains("Gmail"),    "prompt missing Gmail label")
        XCTAssertTrue(capturedPrompt.contains("Calendar"), "prompt missing Calendar label")
        XCTAssertTrue(capturedPrompt.contains("Notion"),   "prompt missing Notion label")
        XCTAssertTrue(capturedPrompt.contains("Drive"),    "prompt missing Drive label")
        XCTAssertTrue(capturedPrompt.contains("Slack"),    "prompt missing Slack label")
        XCTAssertTrue(capturedPrompt.contains("GitHub"),   "prompt missing GitHub label")
        XCTAssertTrue(capturedPrompt.contains("Linear"),   "prompt missing Linear label")
    }

    /// 3 of 7 return ""; the prompt should only contain the 4 non-empty labels.
    func testGatherSkipsEmptySources() async {
        let sut = CrossConnectorSynthesizer()
        let sources = makeSources(
            gmail:  "email content",
            gcal:   "",
            notion: "notion content",
            drive:  "",
            slack:  "slack content",
            github: "",
            linear: "linear content"
        )

        var capturedPrompt = ""
        _ = await sut.gather(topic: "topic", sources: sources) { prompt in
            capturedPrompt = prompt
            return "ok"
        }

        XCTAssertTrue(capturedPrompt.contains("Gmail"),    "should contain Gmail")
        XCTAssertTrue(capturedPrompt.contains("Notion"),   "should contain Notion")
        XCTAssertTrue(capturedPrompt.contains("Slack"),    "should contain Slack")
        XCTAssertTrue(capturedPrompt.contains("Linear"),   "should contain Linear")
        XCTAssertFalse(capturedPrompt.contains("Calendar"), "should skip empty Calendar")
        XCTAssertFalse(capturedPrompt.contains("Drive"),    "should skip empty Drive")
        XCTAssertFalse(capturedPrompt.contains("GitHub"),   "should skip empty GitHub")
    }

    /// All sources return ""; gather returns the not-found fallback without calling synthesize.
    func testGatherReturnsNotFoundWhenAllEmpty() async {
        let sut = CrossConnectorSynthesizer()
        let sources = makeSources()

        var synthesizerCalled = false
        let result = await sut.gather(topic: "widgets", sources: sources) { _ in
            synthesizerCalled = true
            return "should not get here"
        }

        XCTAssertFalse(synthesizerCalled, "synthesize should not be called when all sources empty")
        XCTAssertTrue(result.contains("didn't find anything"), "expected not-found message, got: \(result)")
    }

    /// synthesize throws; gather returns concatenated labeled fallback (no crash, no throw).
    func testGatherFallbackOnSynthesizeError() async {
        let sut = CrossConnectorSynthesizer()
        let sources = makeSources(gmail: "email stuff", linear: "linear stuff")

        enum TestError: Error { case boom }
        let result = await sut.gather(topic: "testing", sources: sources) { _ in
            throw TestError.boom
        }

        XCTAssertTrue(result.contains("[Gmail]"),  "fallback should contain Gmail label")
        XCTAssertTrue(result.contains("[Linear]"), "fallback should contain Linear label")
        XCTAssertTrue(result.contains("email stuff"),  "fallback should contain Gmail content")
        XCTAssertTrue(result.contains("linear stuff"), "fallback should contain Linear content")
    }

    /// synthesize returns ""; gather returns fallback concatenated content.
    func testGatherFallbackOnEmptySynthesizeResult() async {
        let sut = CrossConnectorSynthesizer()
        let sources = makeSources(notion: "notion pages", drive: "drive files")

        let result = await sut.gather(topic: "docs", sources: sources) { _ in "" }

        XCTAssertTrue(result.contains("[Notion]"), "fallback should contain Notion label")
        XCTAssertTrue(result.contains("[Drive]"),  "fallback should contain Drive label")
        XCTAssertTrue(result.contains("notion pages"), "fallback should contain Notion content")
        XCTAssertTrue(result.contains("drive files"),  "fallback should contain Drive content")
    }

    /// All sources return ""; the not-found message contains the topic string.
    func testGatherReturnsNotFoundMessageForUnknownTopic() async {
        let sut = CrossConnectorSynthesizer()
        let sources = makeSources()

        let result = await sut.gather(topic: "xyz123nonexistent", sources: sources) { _ in "" }

        XCTAssertTrue(result.contains("xyz123nonexistent"),
                      "not-found message should include the topic, got: \(result)")
    }

    /// Concurrency: verify all 7 closures are actually invoked (the async let fan-out works).
    func testGatherInvokesAllSourcesConcurrently() async {
        let sut = CrossConnectorSynthesizer()

        // Track which sources ran using an actor to satisfy Swift 6 concurrency rules.
        actor Tracker {
            var called: Set<String> = []
            func mark(_ label: String) { called.insert(label) }
        }
        let tracker = Tracker()

        let sources = CrossConnectorSynthesizer.Sources(
            gmail:  { _ in await tracker.mark("gmail");  return "g" },
            gcal:   { _ in await tracker.mark("gcal");   return "c" },
            notion: { _ in await tracker.mark("notion"); return "n" },
            drive:  { _ in await tracker.mark("drive");  return "d" },
            slack:  { _ in await tracker.mark("slack");  return "s" },
            github: { _ in await tracker.mark("github"); return "gh" },
            linear: { _ in await tracker.mark("linear"); return "li" }
        )

        _ = await sut.gather(topic: "anything", sources: sources) { _ in "done" }

        let called = await tracker.called
        XCTAssertEqual(called, ["gmail", "gcal", "notion", "drive", "slack", "github", "linear"],
                       "not all sources were called")
    }
}
