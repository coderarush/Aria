import XCTest
@testable import Aria

final class UndoStackTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-undo-\(UUID().uuidString).txt")
    }

    func testRevertOverwriteRestoresPreviousContents() async throws {
        let url = tempFile()
        try "ORIGINAL".write(to: url, atomically: true, encoding: .utf8)
        try "CHANGED".write(to: url, atomically: true, encoding: .utf8)

        let result = await UndoStack.revert(.fileWrite(path: url.path, previousContent: "ORIGINAL"))
        XCTAssertTrue(result.success)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "ORIGINAL")
        try? FileManager.default.removeItem(at: url)
    }

    func testRevertCreateDeletesFileThatDidNotExistBefore() async throws {
        let url = tempFile()
        try "NEW".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let result = await UndoStack.revert(.fileWrite(path: url.path, previousContent: nil))
        XCTAssertTrue(result.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testUndoLastIsLIFOAndReportsEmpty() async throws {
        let stack = UndoStack()
        let a = tempFile(); let b = tempFile()
        try "A".write(to: a, atomically: true, encoding: .utf8)
        try "B".write(to: b, atomically: true, encoding: .utf8)
        await stack.record(.fileWrite(path: a.path, previousContent: nil))
        await stack.record(.fileWrite(path: b.path, previousContent: nil))

        let d0 = await stack.depth(); XCTAssertEqual(d0, 2)
        _ = await stack.undoLast()                              // undoes B (newest) first
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        _ = await stack.undoLast()                              // then A
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))

        let empty = await stack.undoLast()
        XCTAssertFalse(empty.success)
        XCTAssertEqual(empty.output, "Nothing to undo.")
    }

    func testCapEvictsOldest() async {
        let stack = UndoStack(cap: 2)
        await stack.record(.clipboardWrite(previous: "1"))
        await stack.record(.clipboardWrite(previous: "2"))
        await stack.record(.clipboardWrite(previous: "3"))
        let depth = await stack.depth()
        XCTAssertEqual(depth, 2)                                // oldest ("1") evicted
    }

    func testLabels() {
        XCTAssertEqual(ReversibleAction.fileWrite(path: "/a/b/notes.txt", previousContent: nil).label, "creating notes.txt")
        XCTAssertEqual(ReversibleAction.fileWrite(path: "/a/b/notes.txt", previousContent: "x").label, "overwriting notes.txt")
        XCTAssertEqual(ReversibleAction.clipboardWrite(previous: nil).label, "changing the clipboard")
    }
}
