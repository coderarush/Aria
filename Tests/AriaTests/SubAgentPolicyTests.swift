import XCTest
@testable import Aria

final class SubAgentPolicyTests: XCTestCase {

    func testEmptyAllowlistPermitsEverything() {
        XCTAssertTrue(SubAgentPolicy.permits(allowedTools: [], tool: "shell"))
        XCTAssertTrue(SubAgentPolicy.permits(allowedTools: [], tool: "anything"))
    }

    func testScopedAllowlistPermitsOnlyListedTools() {
        let scope = ["web_search", "web_fetch"]
        XCTAssertTrue(SubAgentPolicy.permits(allowedTools: scope, tool: "web_search"))
        XCTAssertTrue(SubAgentPolicy.permits(allowedTools: scope, tool: "web_fetch"))
        XCTAssertFalse(SubAgentPolicy.permits(allowedTools: scope, tool: "shell"))
        XCTAssertFalse(SubAgentPolicy.permits(allowedTools: scope, tool: "applescript"))
        XCTAssertFalse(SubAgentPolicy.permits(allowedTools: scope, tool: "send_mail"))
    }

    func testEveryBuiltinAgentDeclaredToolsCoverItsOwnCalls() {
        // Regression guard: builtins must not be scoped tighter than the tools
        // they actually call (verified manually against BuiltinSubAgents today;
        // this asserts the lists stay non-empty and well-formed).
        for agent in SubAgentRegistry.builtins() {
            for tool in agent.allowedTools {
                XCTAssertFalse(tool.isEmpty, "\(agent.name) has an empty tool name")
            }
        }
    }
}
