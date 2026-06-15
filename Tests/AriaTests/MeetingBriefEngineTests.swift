import XCTest
@testable import Aria

final class MeetingBriefEngineTests: XCTestCase {

    // MARK: - MeetingBriefEngine tests

    func testBriefCombinesConnectorResults() async {
        let engine = MeetingBriefEngine()
        let connectors = MeetingBriefEngine.ConnectorTools(
            gmailRecent: { _ in "Email thread about Q3 budget" },
            notionSearch: { _ in "Notion doc: Project roadmap notes" },
            driveSearch: { _ in "Drive file: Meeting agenda.pdf" }
        )
        let title = "Q3 Planning"
        let result = await engine.brief(
            for: title,
            attendees: ["alice@example.com", "bob@example.com"],
            connectorTools: connectors,
            synthesize: { _ in "Here is your brief about \(title)" }
        )
        XCTAssertTrue(result.contains(title), "Result should contain event title, got: \(result)")
    }

    func testBriefFallbackWhenAllConnectorsEmpty() async {
        let engine = MeetingBriefEngine()
        let connectors = MeetingBriefEngine.ConnectorTools(
            gmailRecent: { _ in "" },
            notionSearch: { _ in "" },
            driveSearch: { _ in "" }
        )
        let title = "Design Review"
        let result = await engine.brief(
            for: title,
            attendees: ["carol@example.com"],
            connectorTools: connectors,
            synthesize: { _ in "Some synthesized text" }
        )
        // When all connectors empty, fallback is returned (no context to synthesize)
        XCTAssertTrue(result.contains(title), "Fallback should contain event title, got: \(result)")
    }

    func testBriefFallbackOnGeminiError() async {
        let engine = MeetingBriefEngine()
        let connectors = MeetingBriefEngine.ConnectorTools(
            gmailRecent: { _ in "Some email context" },
            notionSearch: { _ in "Some notion context" },
            driveSearch: { _ in "Some drive context" }
        )
        let title = "Investor Call"
        let result = await engine.brief(
            for: title,
            attendees: ["investor@vc.com"],
            connectorTools: connectors,
            synthesize: { _ in throw NSError(domain: "GeminiError", code: 500, userInfo: nil) }
        )
        // No throw propagation — fallback returned
        XCTAssertTrue(result.contains(title), "Fallback on error should contain title, got: \(result)")
    }

    func testBriefFallbackIncludesAttendeesWhenPresent() async {
        let engine = MeetingBriefEngine()
        let connectors = MeetingBriefEngine.ConnectorTools(
            gmailRecent: { _ in "" },
            notionSearch: { _ in "" },
            driveSearch: { _ in "" }
        )
        let title = "Team Sync"
        let attendees = ["alice@example.com", "bob@example.com"]
        let result = await engine.brief(
            for: title,
            attendees: attendees,
            connectorTools: connectors,
            synthesize: { _ in throw NSError(domain: "GeminiError", code: 500, userInfo: nil) }
        )
        XCTAssertTrue(result.contains("alice@example.com"), "Fallback should include attendees, got: \(result)")
    }

    func testBriefFallbackNoAttendeesSection() async {
        let engine = MeetingBriefEngine()
        let connectors = MeetingBriefEngine.ConnectorTools(
            gmailRecent: { _ in "" },
            notionSearch: { _ in "" },
            driveSearch: { _ in "" }
        )
        let title = "Focus Block"
        let result = await engine.brief(
            for: title,
            attendees: [],
            connectorTools: connectors,
            synthesize: { _ in throw NSError(domain: "GeminiError", code: 500, userInfo: nil) }
        )
        XCTAssertFalse(result.contains("Attendees:"), "Fallback with no attendees should not include Attendees: label, got: \(result)")
        XCTAssertTrue(result.contains(title))
    }

    // MARK: - CalendarSignalProvider + UpcomingEvent (attendees) tests

    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testCalendarSignalWithAttendeesRunsCommand() async {
        let event = UpcomingEvent(
            id: "meet1",
            title: "Product Review",
            start: now.addingTimeInterval(300),
            attendees: ["alice@example.com", "bob@example.com"]
        )
        let provider = CalendarSignalProvider(leadWindow: 900) { _ in [event] }
        let suggestions = await provider.candidates(now: now)
        XCTAssertEqual(suggestions.count, 1)
        guard case .runCommand(let cmd) = suggestions[0].action else {
            XCTFail("Expected .runCommand, got \(suggestions[0].action)")
            return
        }
        XCTAssertTrue(cmd.contains("Product Review"), "Command should contain event title, got: \(cmd)")
    }

    func testCalendarSignalWithoutAttendeesAcknowledges() async {
        let event = UpcomingEvent(
            id: "block1",
            title: "Deep Work",
            start: now.addingTimeInterval(300),
            attendees: []
        )
        let provider = CalendarSignalProvider(leadWindow: 900) { _ in [event] }
        let suggestions = await provider.candidates(now: now)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].action, .acknowledge)
    }

    func testCalendarSignalWithAttendeesHasBriefingSpokenLine() async {
        let event = UpcomingEvent(
            id: "meet2",
            title: "Weekly Standup",
            start: now.addingTimeInterval(600),
            attendees: ["carol@example.com"]
        )
        let provider = CalendarSignalProvider(leadWindow: 900) { _ in [event] }
        let suggestions = await provider.candidates(now: now)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertTrue(suggestions[0].spokenLine.contains("Weekly Standup"))
        XCTAssertTrue(suggestions[0].spokenLine.lowercased().contains("brief"),
                      "spokenLine should mention briefing, got: \(suggestions[0].spokenLine)")
    }

    func testLeadWindowDefaultIs15Minutes() {
        let provider = CalendarSignalProvider { _ in [] }
        XCTAssertEqual(provider.leadWindow, 900, "Default leadWindow should be 900 seconds (15 minutes)")
    }
}
