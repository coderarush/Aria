import XCTest
@testable import Aria

final class DigestEngineTests: XCTestCase {

    // MARK: Helpers

    private let engine = DigestEngine()

    private func validJSON(
        accomplishments: [String] = ["Finished the report", "Sent emails"],
        overdueItems: [String] = ["Follow up with Alice"],
        tomorrowPreview: String = "Team standup at 9am"
    ) -> String {
        let accs = accomplishments.map { "\"\($0)\"" }.joined(separator: ",")
        let over = overdueItems.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"date":"Monday","summary":"A productive day.","accomplishments":[\(accs)],"overdueItems":[\(over)],"tomorrowPreview":"\(tomorrowPreview)"}
        """
    }

    // MARK: Tests

    func testGeneratesDigest() async {
        let json = validJSON()
        let digest = await engine.generate(
            timeline: "worked on report",
            followUps: "none",
            tomorrowCalendar: "Team standup at 9am",
            synthesize: { _ in json }
        )
        XCTAssertFalse(digest.summary.isEmpty, "summary should not be empty")
    }

    func testFallbackOnBadJSON() async {
        let digest = await engine.generate(
            timeline: "worked on things",
            followUps: "some overdue",
            tomorrowCalendar: "Dentist at 2pm",
            synthesize: { _ in "bad json not parseable" }
        )
        // Should not throw — returns fallback
        XCTAssertFalse(digest.summary.isEmpty)
        XCTAssertEqual(digest.summary, "Here's your end-of-day summary.")
    }

    func testAccomplishmentsPopulated() async {
        let json = validJSON(accomplishments: ["Shipped feature", "Fixed bug"])
        let digest = await engine.generate(
            timeline: "busy day",
            followUps: "none",
            tomorrowCalendar: "nothing",
            synthesize: { _ in json }
        )
        XCTAssertEqual(digest.accomplishments.count, 2)
    }

    func testOverdueItemsPopulated() async {
        let json = validJSON(overdueItems: ["Reply to Bob", "Send invoice"])
        let digest = await engine.generate(
            timeline: "busy day",
            followUps: "overdue items",
            tomorrowCalendar: "nothing",
            synthesize: { _ in json }
        )
        XCTAssertEqual(digest.overdueItems.count, 2)
    }

    func testTomorrowPreviewPresent() async {
        let json = validJSON(tomorrowPreview: "Board meeting at 10am")
        let digest = await engine.generate(
            timeline: "quiet day",
            followUps: "none",
            tomorrowCalendar: "Board meeting at 10am",
            synthesize: { _ in json }
        )
        XCTAssertTrue(digest.tomorrowPreview.contains("Board meeting"))
    }
}
