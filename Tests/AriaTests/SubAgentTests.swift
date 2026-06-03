import XCTest
@testable import Aria

final class SubAgentTests: XCTestCase {

    func testRegistryHasBuiltins() async {
        let registry = SubAgentRegistry()
        let research = await registry.agent(named: "research")
        XCTAssertNotNil(research)
        let catalog = await registry.catalog()
        XCTAssertTrue(catalog.contains("research:"))
        XCTAssertTrue(catalog.contains("code_writer:"))
        XCTAssertTrue(catalog.contains("task_planner:"))
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
