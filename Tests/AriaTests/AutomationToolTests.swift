import XCTest
@testable import Aria

final class AutomationToolTests: XCTestCase {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-automation-\(UUID().uuidString).json")
    }

    private func store() -> AgentStore {
        AgentStore(fileURL: tempStoreURL())
    }

    func testCreateEmailAutomation() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Boss emails",
            "trigger_type": "email",
            "trigger_value": "from:boss@company.com",
            "goal": "Summarize and notify"
        ])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Boss emails"))
        XCTAssertTrue(result.output.contains("from:boss@company.com"))

        // Verify it was stored
        let all = await store.all()
        let stored = all.first { $0.name == "Boss emails" }
        XCTAssertNotNil(stored)
        if case .mailMatched(let q) = stored?.trigger {
            XCTAssertEqual(q, "from:boss@company.com")
        } else {
            XCTFail("Expected mailMatched trigger")
        }
    }

    func testCreateCalendarAutomationUsesInjectedStore() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Standup prep",
            "trigger_type": "calendar",
            "trigger_value": "Standup",
            "goal": "Prepare standup notes"
        ])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Standup prep"))

        let all = await store.all()
        let stored = all.first { $0.name == "Standup prep" }
        XCTAssertNotNil(stored)
        if case .calendarEventSoon(let title, let mins) = stored?.trigger {
            XCTAssertEqual(title, "Standup")
            XCTAssertEqual(mins, 10)
        } else {
            XCTFail("Expected calendarEventSoon trigger")
        }
    }

    func testCreateDailyAutomation() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Morning briefing",
            "trigger_type": "daily",
            "trigger_value": "09:00",
            "goal": "Send daily briefing"
        ])
        XCTAssertTrue(result.success)

        let all = await store.all()
        let stored = all.first { $0.name == "Morning briefing" }
        XCTAssertNotNil(stored)
        if case .daily(let h, let m) = stored?.trigger {
            XCTAssertEqual(h, 9)
            XCTAssertEqual(m, 0)
        } else {
            XCTFail("Expected daily trigger")
        }
    }

    func testCreateIntervalAutomation() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Hourly check",
            "trigger_type": "interval",
            "trigger_value": "3600",
            "goal": "Check for updates"
        ])
        XCTAssertTrue(result.success)

        let all = await store.all()
        let stored = all.first { $0.name == "Hourly check" }
        XCTAssertNotNil(stored)
        if case .interval(let s) = stored?.trigger {
            XCTAssertEqual(s, 3600)
        } else {
            XCTFail("Expected interval trigger")
        }
    }

    func testCreateMissingNameReturnsError() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "trigger_type": "email",
            "trigger_value": "from:boss",
            "goal": "Do something"
        ])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.lowercased().contains("missing"))
    }

    func testCreateMissingGoalReturnsError() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Test",
            "trigger_type": "email",
            "trigger_value": "from:boss"
        ])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.lowercased().contains("missing"))
    }

    func testCreateBadDailyFormatReturnsError() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Bad daily",
            "trigger_type": "daily",
            "trigger_value": "not-a-time",
            "goal": "Do something"
        ])
        XCTAssertFalse(result.success)
    }

    func testCreateBadIntervalFormatReturnsError() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Bad interval",
            "trigger_type": "interval",
            "trigger_value": "notanumber",
            "goal": "Do something"
        ])
        XCTAssertFalse(result.success)
    }

    func testCreateUnknownTriggerTypeReturnsError() async throws {
        let store = store()
        let tool = AutomationCreateTool(store: store)
        let result = try await tool.run(input: [
            "name": "Bad type",
            "trigger_type": "webhook",
            "trigger_value": "whatever",
            "goal": "Do something"
        ])
        XCTAssertFalse(result.success)
    }

    func testListReadsOnlyItsInjectedStore() async throws {
        let store = store()
        _ = try await AutomationCreateTool(store: store).run(input: [
            "name": "List test agent",
            "trigger_type": "email",
            "trigger_value": "from:alice",
            "goal": "Reply to Alice"
        ])

        let result = try await AutomationListTool(store: store).run(input: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("List test agent"))
        XCTAssertTrue(result.output.contains("Goal: Reply to Alice"))
    }

    func testTriggerDescriptionCalendarEventSoon() {
        let trigger = AgentTrigger.calendarEventSoon(titleContains: "Standup", minutesBefore: 15)
        let desc = triggerDescription(trigger)
        XCTAssertTrue(desc.contains("Standup"))
        XCTAssertTrue(desc.contains("15"))
    }

    func testTriggerDescriptionEmail() {
        let desc = triggerDescription(.mailMatched(query: "from:boss"))
        XCTAssertTrue(desc.contains("from:boss"))
    }

    func testTriggerDescriptionDaily() {
        let desc = triggerDescription(.daily(hour: 9, minute: 5))
        XCTAssertEqual(desc, "daily at 09:05")
    }

    func testTriggerDescriptionInterval() {
        let desc = triggerDescription(.interval(seconds: 1800))
        XCTAssertTrue(desc.contains("30"))  // 1800s = 30 min
    }
}
