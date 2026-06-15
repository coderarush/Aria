import XCTest
@testable import Aria

final class StyleLearnerTests: XCTestCase {
    private func learner(enabled: Bool) -> StyleLearner {
        let d = UserDefaults(suiteName: "style-\(UUID().uuidString)")!
        d.set(enabled, forKey: StyleLearner.enabledKey)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("style-\(UUID().uuidString).json")
        return StyleLearner(storeURL: url, defaults: d)
    }

    func testOffNeverLearnsNoInstruction() async {
        let l = learner(enabled: false)
        await l.observe("hey can you send this over thanks")
        let inst = await l.draftStyleInstruction()
        XCTAssertNil(inst, "personalization off → no style injection")
    }

    func testOnLearnsAndGivesDraftScopedInstruction() async {
        let l = learner(enabled: true)
        await l.observe("hey can you fire that over real quick thanks")
        await l.observe("yeah sounds good lmk when its done")
        let inst = await l.draftStyleInstruction()
        XCTAssertNotNil(inst)
        XCTAssertTrue(inst!.lowercased().contains("draft"), inst ?? "")
    }

    func testTrivialSamplesSkipped() async {
        let l = learner(enabled: true)
        await l.observe("ok")            // < 8 chars, ignored
        let inst = await l.draftStyleInstruction()
        XCTAssertNil(inst)               // nothing real learned yet
    }
}
