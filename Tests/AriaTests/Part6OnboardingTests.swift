import XCTest
@testable import Aria

final class Part6OnboardingTests: XCTestCase {

    // MARK: - OnboardingEngine (§117)

    func testStartsAtWelcome() async {
        let engine = OnboardingEngine()
        let step = await engine.step
        XCTAssertEqual(step, .welcome)
    }

    func testAdvanceReachesContinuationThenCompletes() async {
        let engine = OnboardingEngine()
        for _ in 0..<4 { await engine.advance() }   // welcome→permission→firstObjective→firstSuccess→continuation
        let step = await engine.step
        XCTAssertEqual(step, .continuation)
        await engine.advance()
        let done = await engine.isComplete()
        XCTAssertTrue(done)
    }

    func testTimeToValueUnderThreeMinutes() {
        XCTAssertLessThanOrEqual(OnboardingEngine.estimatedSeconds, 180)
    }

    // MARK: - DefaultExperience (§118)

    func testEntryPointsCoverAll() {
        let experience = DefaultExperience()
        XCTAssertEqual(Set(experience.entryPoints), Set(EntryPoint.allCases))
    }

    func testObjectiveFirstChatSecond() {
        let surface = DefaultExperience().surface(for: .hotkey)
        XCTAssertEqual(surface.first, "objective")
        let objectiveIndex = surface.firstIndex(of: "objective")!
        let chatIndex = surface.firstIndex(of: "chat")!
        XCTAssertLessThan(objectiveIndex, chatIndex)
    }
}
