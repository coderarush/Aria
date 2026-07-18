import XCTest
@testable import Aria

final class AssistantBenchmarkToolTests: XCTestCase {

    func testBenchmarkReportIncludesCoreDimensionsAndAriaFocusUpgrade() {
        let report = AssistantBenchmarkEngine.report(focus: "Aria")

        XCTAssertEqual(report.focus, "Aria")
        XCTAssertTrue(report.rows.contains(where: { $0.area == "Autonomy" }))
        XCTAssertTrue(report.rows.contains(where: { $0.aria.contains("background agents") }))
        XCTAssertTrue(report.strengths.contains(where: { $0.contains("voice") }))
        XCTAssertTrue(report.gaps.contains(where: { $0.contains("conversation history") }))
        XCTAssertEqual(report.nextUpgrades.first, "Run an ARIA-specific build loop: audit → implement → test → update website/video → save launch notes.")
    }

    func testBenchmarkToolReturnsReadableMatrix() async throws {
        let result = try await AssistantBenchmarkTool().run(input: ["focus": "Aria"])

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Capability matrix"))
        XCTAssertTrue(result.output.contains("Aria advantages"))
        XCTAssertTrue(result.output.contains("Next upgrades"))
    }
}
