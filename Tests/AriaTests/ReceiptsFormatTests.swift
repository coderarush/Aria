import XCTest
@testable import Aria

/// Pure-helper tests for the Receipts pane: importance → label/colour and the
/// relative-time + tool prettifier. No window, no actor — every method under test
/// is deterministic and `nonisolated`.
final class ReceiptsFormatTests: XCTestCase {

    func testImportanceLabels() {
        XCTAssertEqual(ReceiptsFormat.importanceLabel(.routine), "Routine")
        XCTAssertEqual(ReceiptsFormat.importanceLabel(.reversible), "Reversible")
        XCTAssertEqual(ReceiptsFormat.importanceLabel(.importantIrreversible), "Important")
    }

    /// Each importance level maps to a distinct tint — the colour-coding is the
    /// whole point of the pill, so a collision would be a real bug.
    func testImportanceColorsAreDistinct() {
        let routine = ReceiptsFormat.importanceColor(.routine)
        let reversible = ReceiptsFormat.importanceColor(.reversible)
        let important = ReceiptsFormat.importanceColor(.importantIrreversible)
        XCTAssertNotEqual(routine, reversible)
        XCTAssertNotEqual(reversible, important)
        XCTAssertNotEqual(routine, important)
    }

    func testRelativeTimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ReceiptsFormat.relativeTime(now, now: now), "just now")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-3600), now: now), "1h ago")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-90_000), now: now), "yesterday")
        XCTAssertEqual(ReceiptsFormat.relativeTime(now.addingTimeInterval(-3 * 86_400), now: now), "3d ago")
    }

    func testPrettyTool() {
        XCTAssertEqual(ReceiptsFormat.prettyTool("send_mail"), "Send mail")
        XCTAssertEqual(ReceiptsFormat.prettyTool("file_write"), "File write")
        XCTAssertEqual(ReceiptsFormat.prettyTool("clipboard.copy"), "Clipboard copy")
        XCTAssertEqual(ReceiptsFormat.prettyTool(""), "")
    }
}
