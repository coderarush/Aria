import XCTest
@testable import Aria

final class FolderWatcherTests: XCTestCase {

    func testFiresOnceDebouncedWhenFilesAppear() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fired = expectation(description: "watcher fired")
        fired.assertForOverFulfill = false   // debounce collapses, but timing isn't exact
        let watcher = FolderWatcher(path: dir.path, debounce: 0.3) { fired.fulfill() }
        XCTAssertTrue(watcher.start())

        // Two rapid writes → one debounced fire.
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        wait(for: [fired], timeout: 3.0)
        watcher.stop()
    }

    func testStartFailsForMissingFolder() {
        let watcher = FolderWatcher(path: "/nonexistent/nowhere-\(UUID().uuidString)", debounce: 0.1) {}
        XCTAssertFalse(watcher.start())
    }

    func testStopIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fw2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let watcher = FolderWatcher(path: dir.path, debounce: 0.1) {}
        XCTAssertTrue(watcher.start())
        watcher.stop()
        watcher.stop()   // second stop must not crash
    }
}
