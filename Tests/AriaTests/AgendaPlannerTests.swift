import XCTest
@testable import Aria

final class AgendaPlannerTests: XCTestCase {

    private let planner = AgendaPlanner()

    private let validPlanJSON = """
    {
      "date": "today",
      "items": [
        {"time": "9:00 AM", "title": "Standup", "type": "meeting", "durationMinutes": 15, "notes": "Daily sync"},
        {"time": "10:00 AM", "title": "Deep Work", "type": "focus", "durationMinutes": 90, "notes": "Work on feature X"},
        {"time": "12:00 PM", "title": "Lunch", "type": "break", "durationMinutes": 60, "notes": "Rest"}
      ],
      "focusSuggestion": "Block 10am-12pm for deep work on the main project.",
      "summary": "A balanced day with meetings in the morning and focus time later."
    }
    """

    func testPlanReturnsDayPlan() async throws {
        let synthesize: @Sendable (String) async throws -> String = { [validPlanJSON] _ in validPlanJSON }
        let plan = try await planner.plan(
            calendarEvents: "Standup at 9am",
            reminders: "Submit report",
            recentWork: "Working on feature X",
            synthesize: synthesize
        )
        XCTAssertFalse(plan.items.isEmpty)
        XCTAssertFalse(plan.summary.isEmpty)
        XCTAssertEqual(plan.items.count, 3)
    }

    func testPlanHandlesBadJSON() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in "bad json here" }
        let plan = try await planner.plan(
            calendarEvents: "Team meeting at 2pm",
            reminders: "None",
            recentWork: "None",
            synthesize: synthesize
        )
        // Should return fallback plan, not throw
        XCTAssertEqual(plan.date, "today")
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.summary.contains("Could not generate plan"))
        XCTAssertTrue(plan.summary.contains("Team meeting at 2pm"))
    }

    func testPlanIncludesMeetings() async throws {
        let meetingJSON = """
        {
          "date": "today",
          "items": [
            {"time": "9:00 AM", "title": "Standup", "type": "meeting", "durationMinutes": 15, "notes": "Daily sync"}
          ],
          "focusSuggestion": "Focus in the afternoon.",
          "summary": "Short day with one meeting."
        }
        """
        let synthesize: @Sendable (String) async throws -> String = { _ in meetingJSON }
        let plan = try await planner.plan(
            calendarEvents: "Standup at 9am",
            reminders: "",
            recentWork: "",
            synthesize: synthesize
        )
        let titles = plan.items.map { $0.title }
        XCTAssertTrue(titles.contains("Standup"))
    }

    func testPlanFocusSuggestionPresent() async throws {
        let synthesize: @Sendable (String) async throws -> String = { [validPlanJSON] _ in validPlanJSON }
        let plan = try await planner.plan(
            calendarEvents: "",
            reminders: "",
            recentWork: "",
            synthesize: synthesize
        )
        XCTAssertFalse(plan.focusSuggestion.isEmpty)
    }

    func testPlanFallbackWhenSynthesizeThrows() async throws {
        let synthesize: @Sendable (String) async throws -> String = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let plan = try await planner.plan(
            calendarEvents: "Nothing",
            reminders: "None",
            recentWork: "None",
            synthesize: synthesize
        )
        // Should return fallback, not throw
        XCTAssertEqual(plan.date, "today")
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.summary.contains("Could not generate plan"))
    }
}
