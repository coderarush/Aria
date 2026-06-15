import XCTest
@testable import Aria

final class UIRecorderTests: XCTestCase {

    // MARK: Helpers

    /// Temp RecipeStore backed by a throw-away file so tests don't touch production data.
    private func tempStore() -> RecipeStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-recipes-\(UUID().uuidString).json")
        return RecipeStore(fileURL: url)
    }

    /// Sendable box for passing a handler across actor boundaries in tests.
    private final class HandlerBox: @unchecked Sendable {
        var handler: (@Sendable (ActionReceipt) -> Void)?
        let lock = NSLock()
        func set(_ h: @escaping @Sendable (ActionReceipt) -> Void) {
            lock.withLock { handler = h }
        }
        func call(_ r: ActionReceipt) {
            lock.withLock { handler }?(r)
        }
    }

    /// A fresh UIRecorder with injected action observation (no real NotificationCenter).
    private func makeRecorder() async -> (UIRecorder, HandlerBox) {
        let recorder = UIRecorder()
        let box = HandlerBox()

        await recorder.setObserveActions { handler in
            box.set(handler)
            return NSObject()
        }

        return (recorder, box)
    }

    /// Make an ActionReceipt for the given tool.
    private func receipt(tool: String,
                         summary: String = "test action",
                         reversible: ReversibleAction? = nil) -> ActionReceipt {
        ActionReceipt(
            id: UUID(),
            summary: summary,
            tool: tool,
            importance: .routine,
            reversible: reversible,
            at: Date()
        )
    }

    // MARK: Tests

    func testStartSetsIsRecording() async {
        let (recorder, _) = await makeRecorder()
        await recorder.startRecording(name: "My Workflow")
        let isRecording = await recorder.isRecording
        XCTAssertTrue(isRecording)
    }

    func testCapturesOpenAppAction() async {
        let (recorder, box) = await makeRecorder()
        await recorder.startRecording(name: "Open Safari")

        box.call(receipt(tool: "open_app", summary: "Safari"))
        try? await Task.sleep(nanoseconds: 30_000_000)

        let steps = await recorder.capturedSteps
        XCTAssertEqual(steps.count, 1, "Expected 1 captured step")
        XCTAssertEqual(steps.first?.tool, "open_app")
    }

    func testStopSavesToRecipeStore() async throws {
        let store = tempStore()
        let (recorder, box) = await makeRecorder()
        await recorder.startRecording(name: "My Workflow")

        box.call(receipt(tool: "open_app", summary: "Safari"))
        box.call(receipt(tool: "save_note", summary: "Meeting notes"))
        try? await Task.sleep(nanoseconds: 40_000_000)

        let recipe = try await recorder.stopRecording(store: store)
        XCTAssertEqual(recipe.name, "My Workflow")
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertEqual(recipe.steps[0].tool, "open_app")
        XCTAssertEqual(recipe.steps[1].tool, "save_note")

        let stored = await store.named("My Workflow")
        XCTAssertNotNil(stored, "Recipe should be persisted in the store")
    }

    func testStopWithNoStepsThrows() async {
        let (recorder, _) = await makeRecorder()
        await recorder.startRecording(name: "Empty")

        do {
            _ = try await recorder.stopRecording(store: tempStore())
            XCTFail("Expected UIRecordingError.notRecording")
        } catch UIRecordingError.notRecording {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelClearsState() async {
        let (recorder, box) = await makeRecorder()
        await recorder.startRecording(name: "Cancelled")
        box.call(receipt(tool: "open_app", summary: "Safari"))
        try? await Task.sleep(nanoseconds: 30_000_000)

        await recorder.cancel()

        let isRecording = await recorder.isRecording
        let steps = await recorder.capturedSteps
        XCTAssertFalse(isRecording)
        XCTAssertTrue(steps.isEmpty)
    }

    func testSkipsUnmappedActions() async {
        let (recorder, box) = await makeRecorder()
        await recorder.startRecording(name: "Filter Test")

        // Post receipts with tools that have no recipe mapping.
        box.call(receipt(tool: "web_search", summary: "search results"))
        box.call(receipt(tool: "file_read", summary: "readme.txt"))
        try? await Task.sleep(nanoseconds: 40_000_000)

        let steps = await recorder.capturedSteps
        XCTAssertTrue(steps.isEmpty, "Unmapped tools should not produce recipe steps")
    }

    func testShellToolMapsToRunCommand() async {
        let (recorder, box) = await makeRecorder()
        await recorder.startRecording(name: "Shell Test")

        box.call(receipt(tool: "shell", summary: "ls -la"))
        try? await Task.sleep(nanoseconds: 30_000_000)

        let steps = await recorder.capturedSteps
        XCTAssertEqual(steps.first?.tool, "run_command")
    }

    func testClipboardToolMapsToClipboardWrite() async {
        let (recorder, box) = await makeRecorder()
        await recorder.startRecording(name: "Clipboard Test")

        box.call(receipt(
            tool: "clipboard",
            summary: "Copied text",
            reversible: .clipboardWrite(previous: "old text")
        ))
        try? await Task.sleep(nanoseconds: 30_000_000)

        let steps = await recorder.capturedSteps
        XCTAssertEqual(steps.first?.tool, "clipboard_write")
    }
}
