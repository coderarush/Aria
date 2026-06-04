import XCTest
@testable import Aria

final class ToolTests: XCTestCase {

    func testRegistryLookupAndCatalog() async {
        let registry = ToolRegistry()
        let shell = await registry.tool(named: "shell")
        XCTAssertNotNil(shell)
        let missing = await registry.tool(named: "nope")
        XCTAssertNil(missing)
        let catalog = await registry.catalog()
        XCTAssertTrue(catalog.contains("shell:"))
        XCTAssertTrue(catalog.contains("web_search:"))
    }

    func testFileWriteThenRead() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-file-\(UUID().uuidString).txt").path
        let write = try await FileWriteTool().run(input: ["path": path, "content": "hello aria"])
        XCTAssertTrue(write.success)
        let read = try await FileReadTool().run(input: ["path": path])
        XCTAssertEqual(read.output, "hello aria")
        try? FileManager.default.removeItem(atPath: path)
    }

    func testFileWriteIsDestructive() {
        XCTAssertTrue(FileWriteTool().isDestructive)
        XCTAssertFalse(FileReadTool().isDestructive)
    }

    func testShellTool() async throws {
        let result = try await ShellTool().run(input: ["command": "echo registry-ok"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("registry-ok"))
    }

    func testMissingInputThrows() async {
        do {
            _ = try await FileReadTool().run(input: [:])
            XCTFail("expected missingInput")
        } catch let error as ToolError {
            XCTAssertEqual(error, .missingInput("path"))
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testStripHTML() {
        let html = "<html><head><style>x{}</style></head><body><h1>Hi</h1>" +
                   "<script>bad()</script><p>World &amp; more</p></body></html>"
        let text = WebFetchTool.stripHTML(html)
        XCTAssertTrue(text.contains("Hi"))
        XCTAssertTrue(text.contains("World & more"))
        XCTAssertFalse(text.contains("bad()"))
        XCTAssertFalse(text.contains("<"))
    }

    func testWebSearchParsesHTMLResults() {
        // A trimmed sample of DuckDuckGo's html results page.
        let html = """
        <div class="result">
          <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fmics&rut=abc">Best USB Mics 2024</a>
          <a class="result__snippet">Our top pick is the Blue Yeti for most people.</a>
        </div>
        <div class="result">
          <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fother.com%2Freview">Mic Review</a>
          <a class="result__snippet">The Shure MV7 is great for podcasting.</a>
        </div>
        """
        let results = WebSearchTool.parseResults(html)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Best USB Mics 2024")
        XCTAssertEqual(results[0].url, "https://example.com/mics")        // uddg decoded
        XCTAssertTrue(results[0].snippet.contains("Blue Yeti"))
        XCTAssertEqual(results[1].url, "https://other.com/review")
    }

    func testWebSearchRealURLDecodesRedirect() {
        XCTAssertEqual(
            WebSearchTool.realURL(from: "//duckduckgo.com/l/?uddg=https%3A%2F%2Fa.com%2Fb%3Fx%3D1"),
            "https://a.com/b?x=1")
        XCTAssertEqual(WebSearchTool.realURL(from: "https://direct.com/page"), "https://direct.com/page")
    }

    func testClipboardRoundTrip() async throws {
        let marker = "aria-clip-\(UUID().uuidString)"
        let write = try await ClipboardTool().run(input: ["action": "write", "text": marker])
        XCTAssertTrue(write.success)
        let read = try await ClipboardTool().run(input: ["action": "read"])
        XCTAssertEqual(read.output, marker)
    }
}
