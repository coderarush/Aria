import XCTest
@testable import Aria

/// V11 P12 — Focus Mode: enter a mode (open what's needed, close distractions,
/// start the session), work, end it (recap from the timeline). Built on the
/// recipe machinery — a focus mode IS a deterministic plan plus a session
/// bracket around it.
final class FocusModeTests: XCTestCase {

    // MARK: intents

    func testEnterIntentDetectsModeName() {
        XCTAssertEqual(FocusMode.enterIntent("enter focus mode"), "")
        XCTAssertEqual(FocusMode.enterIntent("start developer focus mode"), "developer")
        XCTAssertEqual(FocusMode.enterIntent("Enter Student Focus Mode"), "student")
        XCTAssertNil(FocusMode.enterIntent("open spotify"))
        XCTAssertNil(FocusMode.enterIntent("what is focus mode"))
    }

    func testEndIntentDetected() {
        XCTAssertTrue(FocusMode.isEndIntent("end focus mode"))
        XCTAssertTrue(FocusMode.isEndIntent("exit focus"))
        XCTAssertTrue(FocusMode.isEndIntent("stop focus mode"))
        XCTAssertFalse(FocusMode.isEndIntent("focus on the deck"))
    }

    // MARK: presets + plan building

    func testPresetsExist() {
        for name in ["student", "founder", "developer"] {
            XCTAssertNotNil(FocusMode.preset(named: name), name)
        }
        // Unknown names fall back to the default preset, never nil behavior.
        XCTAssertNotNil(FocusMode.preset(named: ""))
    }

    func testPlanOpensAppsThenClosesDistractions() {
        let mode = FocusMode(name: "developer",
                             openApps: ["Visual Studio Code", "Terminal"],
                             closeApps: ["Messages", "Mail"])
        let steps = mode.taskSteps()
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps[0].executor, .tool("open_app"))
        XCTAssertEqual(steps[0].input["name"], "Visual Studio Code")
        XCTAssertEqual(steps[2].executor, .tool("quit_app"))
        XCTAssertEqual(steps[2].input["name"], "Messages")
    }

    // MARK: session lifecycle

    func testSessionTracksWindowAndRecaps() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-\(UUID().uuidString).json")
        let session = FocusSession(fileURL: url)
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 11; c.hour = 9
        let start = Calendar.current.date(from: c)!

        await session.begin(mode: "developer", at: start)
        let active = await session.active()
        XCTAssertEqual(active?.mode, "developer")

        let ended = await session.end(at: start.addingTimeInterval(3600))
        XCTAssertEqual(ended?.mode, "developer")
        XCTAssertEqual(ended?.startedAt, start)
        let after = await session.active()
        XCTAssertNil(after, "ending clears the active session")
    }

    func testSessionSurvivesRestart() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-\(UUID().uuidString).json")
        await FocusSession(fileURL: url).begin(mode: "student", at: Date())
        let reloaded = FocusSession(fileURL: url)
        let active = await reloaded.active()
        XCTAssertEqual(active?.mode, "student")
    }

    // MARK: quit tool safety

    func testQuitAppRefusesProtectedApps() async throws {
        let tool = QuitAppTool()
        for app in ["Finder", "Aria", "finder"] {
            let result = try await tool.run(input: ["name": app])
            XCTAssertFalse(result.success, "\(app) must never be quit")
        }
    }

    func testQuitAppRequiresName() async {
        let tool = QuitAppTool()
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput")
        } catch { /* expected */ }
    }
}
