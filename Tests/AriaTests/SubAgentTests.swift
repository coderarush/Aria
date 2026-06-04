import XCTest
@testable import Aria

final class SubAgentTests: XCTestCase {

    func testRegistryHasBuiltins() async {
        let registry = SubAgentRegistry()
        let orion = await registry.agent(named: "Orion")
        XCTAssertNotNil(orion)
        let catalog = await registry.catalog()
        XCTAssertTrue(catalog.contains("Orion:"))
        XCTAssertTrue(catalog.contains("Nova:"))
        XCTAssertTrue(catalog.contains("Atlas:"))
        XCTAssertTrue(catalog.contains("Lyra:"))
        XCTAssertTrue(catalog.contains("Comet:"))
    }

    func testCrewPersonas() {
        let crew = SubAgentRegistry.crewInfo()
        XCTAssertEqual(crew.count, 5)
        let orion = crew.first { $0.name == "Orion" }
        XCTAssertEqual(orion?.persona, "tracks down anything on the web")
        let nova = crew.first { $0.name == "Nova" }
        XCTAssertEqual(nova?.persona, "writes and runs code on the fly")
        let atlas = crew.first { $0.name == "Atlas" }
        XCTAssertEqual(atlas?.persona, "operates the Mac — apps, files, system")
        let lyra = crew.first { $0.name == "Lyra" }
        XCTAssertEqual(lyra?.persona, "the wordsmith — drafts and writes")
        let comet = crew.first { $0.name == "Comet" }
        XCTAssertEqual(comet?.persona, "the courier — handles mail and messages")
    }

    func testAllowedTools() {
        let orion = ResearchAgent()
        XCTAssertEqual(orion.allowedTools, ["web_search", "web_fetch"])
        let nova = CodeWriterAgent()
        XCTAssertEqual(nova.allowedTools, ["file_write"])
        let atlas = TaskPlannerAgent()
        XCTAssertTrue(atlas.allowedTools.contains("applescript"))
        let lyra = LyraAgent()
        XCTAssertEqual(lyra.allowedTools, ["file_write", "clipboard"])
        let comet = CometAgent()
        XCTAssertEqual(comet.allowedTools, ["applescript", "clipboard"])
    }

    func testExtractURLs() {
        let text = "See https://swift.org and http://example.com/page for more."
        let urls = ResearchAgent.extractURLs(from: text)
        XCTAssertTrue(urls.contains("https://swift.org"))
        XCTAssertTrue(urls.contains("http://example.com/page"))
    }

    func testParsePlanActions() {
        let raw = """
        ```json
        [{"tool":"web_search","input":{"query":"swift"}},{"tool":"file_write","input":{"path":"/tmp/x","content":"hi"}}]
        ```
        """
        let actions = TaskPlannerAgent.parseActions(raw)
        XCTAssertEqual(actions?.count, 2)
        XCTAssertEqual(actions?.first?.tool, "web_search")
        XCTAssertEqual(actions?.last?.input["path"], "/tmp/x")
    }

    func testParsePlanWithSurroundingText() {
        let raw = "Here is the plan: [{\"tool\":\"notify\",\"input\":{}}] done."
        let actions = TaskPlannerAgent.parseActions(raw)
        XCTAssertEqual(actions?.count, 1)
        XCTAssertEqual(actions?.first?.tool, "notify")
    }

    func testLanguageHint() {
        XCTAssertEqual(AgentContext.languageHint(in: "write a node script"), "javascript")
        XCTAssertEqual(AgentContext.languageHint(in: "a bash one-liner"), "bash")
        XCTAssertEqual(AgentContext.languageHint(in: "parse a csv"), "python")
    }

    func testAgentResultHelpers() {
        XCTAssertTrue(AgentResult.ok("x").success)
        XCTAssertFalse(AgentResult.fail("y").success)
        XCTAssertEqual(AgentResult.ok("x", artifacts: ["/a"]).artifacts, ["/a"])
    }
}
