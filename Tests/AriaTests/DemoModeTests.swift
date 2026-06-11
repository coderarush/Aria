import XCTest
@testable import Aria

final class DemoModeTests: XCTestCase {

    func testDisabledWithoutEnvFlag() {
        XCTAssertFalse(DemoMode.isEnabled(environment: [:]))
        XCTAssertFalse(DemoMode.isEnabled(environment: ["ARIA_DEMO_MODE": "0"]))
        XCTAssertTrue(DemoMode.isEnabled(environment: ["ARIA_DEMO_MODE": "1"]))
    }

    func testBuiltinScriptAnswersMarketingFlows() {
        let reply = DemoMode.reply(for: "prepare me for tomorrow's meeting")
        XCTAssertTrue(reply.contains("briefing"), reply)
        XCTAssertTrue(DemoMode.reply(for: "organize my downloads folder").lowercased().contains("organized"))
        XCTAssertTrue(DemoMode.reply(for: "what did the investor say about pricing").contains("$29"))
    }

    func testUnknownPromptGetsGracefulLine() {
        let reply = DemoMode.reply(for: "xyzzy completely unscripted")
        XCTAssertFalse(reply.isEmpty)
    }

    func testCustomScriptFileOverridesBuiltin() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"weather": "Sunny and 72, all week."}"#.data(using: .utf8)!.write(to: url)
        let script = DemoMode.loadScript(from: url.path)
        XCTAssertEqual(script?["weather"], "Sunny and 72, all week.")
    }

    func testRepliesAreDeterministic() {
        let a = DemoMode.reply(for: "prepare me for tomorrow's meeting")
        let b = DemoMode.reply(for: "prepare me for tomorrow's meeting")
        XCTAssertEqual(a, b, "demo mode must never vary during a recording")
    }
}
