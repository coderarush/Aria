import XCTest
@testable import Aria

final class ToolDeclarationsTests: XCTestCase {
    func testBuildsFunctionDeclarationForATool() {
        let decls = ToolDeclarations.declarations(for: [
            ToolSpec(name: "open_app", description: "Open a Mac app.", params: ["name": "App name"])
        ])
        XCTAssertEqual(decls.count, 1)
        let d = decls[0]
        XCTAssertEqual(d["name"] as? String, "open_app")
        XCTAssertEqual(d["description"] as? String, "Open a Mac app.")
        let params = d["parameters"] as? [String: Any]
        XCTAssertEqual(params?["type"] as? String, "object")
        let props = params?["properties"] as? [String: Any]
        XCTAssertNotNil(props?["name"])
    }
}
