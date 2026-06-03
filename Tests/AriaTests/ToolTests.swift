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
            .appendingPathComponent("friday-file-\(UUID().uuidString).txt").path
        let write = try await FileWriteTool().run(input: ["path": path, "content": "hello friday"])
        XCTAssertTrue(write.success)
        let read = try await FileReadTool().run(input: ["path": path])
        XCTAssertEqual(read.output, "hello friday")
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

    func testWebSearchSummarizeAbstract() {
        let json = #"{"AbstractText":"Swift is a language","AbstractURL":"https://swift.org","RelatedTopics":[]}"#
        let out = WebSearchTool.summarize(Data(json.utf8), query: "swift")
        XCTAssertTrue(out.contains("Swift is a language"))
        XCTAssertTrue(out.contains("swift.org"))
    }

    func testWebSearchSummarizeRelated() {
        let json = #"{"AbstractText":"","RelatedTopics":[{"Text":"Topic one"},{"Text":"Topic two"}]}"#
        let out = WebSearchTool.summarize(Data(json.utf8), query: "x")
        XCTAssertTrue(out.contains("Topic one"))
    }

    func testClipboardRoundTrip() async throws {
        let marker = "friday-clip-\(UUID().uuidString)"
        let write = try await ClipboardTool().run(input: ["action": "write", "text": marker])
        XCTAssertTrue(write.success)
        let read = try await ClipboardTool().run(input: ["action": "read"])
        XCTAssertEqual(read.output, marker)
    }
}
