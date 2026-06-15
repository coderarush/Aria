import XCTest
@testable import Aria

final class ClipboardContextTests: XCTestCase {

    // MARK: Tests

    func testSnapshotReturnsNilWhenClipboardEmpty() async {
        let ctx = ClipboardContext()
        await ctx.setReadClipboard { nil }
        let result = await ctx.snapshot()
        XCTAssertNil(result)
    }

    func testSnapshotReturnsTrimmedContent() async {
        let ctx = ClipboardContext()
        await ctx.setReadClipboard { "  hello  " }
        await ctx.setPollInterval(0.01)

        await ctx.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await ctx.stop()

        let result = await ctx.snapshot()
        XCTAssertEqual(result, "hello")
    }

    func testHistoryKeepsLast5() async {
        let values: [String?] = ["a", "b", "c", "d", "e", "f", "g"]
        let idx = LockProtected(0)
        let ctx = ClipboardContext()
        await ctx.setReadClipboard {
            let i = idx.value
            let v = values[min(i, values.count - 1)]
            if i < values.count - 1 { idx.value += 1 }
            return v
        }
        await ctx.setPollInterval(0.005)

        await ctx.start()
        try? await Task.sleep(nanoseconds: 120_000_000)
        await ctx.stop()

        let history = await ctx.history
        XCTAssertLessThanOrEqual(history.count, 5, "History should be capped at 5")
        XCTAssertEqual(history.count, 5, "History should contain exactly 5 entries")
    }

    func testHistoryDeduplicates() async {
        let values: [String?] = ["hello", "hello", "world"]
        let idx = LockProtected(0)
        let ctx = ClipboardContext()
        await ctx.setReadClipboard {
            let i = idx.value
            let v = values[min(i, values.count - 1)]
            if i < values.count - 1 { idx.value += 1 }
            return v
        }
        await ctx.setPollInterval(0.005)

        await ctx.start()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await ctx.stop()

        let history = await ctx.history
        let helloCount = history.filter { $0 == "hello" }.count
        XCTAssertEqual(helloCount, 1, "Duplicate value should appear only once in history")
    }

    func testCurrentUpdatesOnChange() async {
        let values: [String?] = ["A", "B"]
        let idx = LockProtected(0)
        let ctx = ClipboardContext()
        await ctx.setReadClipboard {
            let i = idx.value
            let v = values[min(i, values.count - 1)]
            if i < values.count - 1 { idx.value += 1 }
            return v
        }
        await ctx.setPollInterval(0.005)

        await ctx.start()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await ctx.stop()

        let current = await ctx.current
        XCTAssertEqual(current, "B")
    }

    func testStartIsIdempotent() async {
        let ctx = ClipboardContext()
        await ctx.setReadClipboard { "test" }
        await ctx.setPollInterval(0.01)
        await ctx.start()
        await ctx.start()  // second call should be a no-op
        await ctx.stop()
        let history = await ctx.history
        XCTAssertLessThanOrEqual(history.count, 5)
    }
}

/// Simple lock-protected box for sharing mutable state across actor boundaries in tests.
final class LockProtected<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
