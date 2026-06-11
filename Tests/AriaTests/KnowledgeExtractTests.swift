import XCTest
@testable import Aria

final class KnowledgeExtractTests: XCTestCase {

    private func tempFile(_ name: String, _ content: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kx-\(UUID().uuidString)-\(name)")
        try? content.data(using: .utf8)?.write(to: url)
        return url
    }

    func testExtractsPlainTextAndMarkdown() {
        let md = tempFile("notes.md", "# Pricing\nThe investor said $29 one-time.")
        defer { try? FileManager.default.removeItem(at: md) }
        let text = TextExtractor.extract(from: md)
        XCTAssertTrue(text?.contains("investor said $29") == true)
    }

    func testExtractsCodeFiles() {
        let swift = tempFile("Foo.swift", "func greet() { print(\"hello\") }")
        defer { try? FileManager.default.removeItem(at: swift) }
        XCTAssertTrue(TextExtractor.extract(from: swift)?.contains("greet") == true)
    }

    func testUnsupportedAndMissingFilesReturnNil() {
        XCTAssertNil(TextExtractor.extract(from: URL(fileURLWithPath: "/nonexistent/x.md")))
        let bin = tempFile("img.dmg", "not really")
        defer { try? FileManager.default.removeItem(at: bin) }
        XCTAssertNil(TextExtractor.extract(from: bin), "unsupported extension must be skipped")
    }

    func testIndexableExtensions() {
        XCTAssertTrue(TextExtractor.isIndexable(URL(fileURLWithPath: "/a/b.md")))
        XCTAssertTrue(TextExtractor.isIndexable(URL(fileURLWithPath: "/a/b.pdf")))
        XCTAssertTrue(TextExtractor.isIndexable(URL(fileURLWithPath: "/a/b.swift")))
        XCTAssertFalse(TextExtractor.isIndexable(URL(fileURLWithPath: "/a/b.zip")))
        XCTAssertFalse(TextExtractor.isIndexable(URL(fileURLWithPath: "/a/b.app")))
    }
}

final class ChunkerTests: XCTestCase {

    func testShortTextIsOneChunk() {
        let chunks = Chunker.chunks(of: "short text", target: 800)
        XCTAssertEqual(chunks, ["short text"])
    }

    func testLongTextSplitsNearTargetOnParagraphs() {
        let para = String(repeating: "word ", count: 100).trimmingCharacters(in: .whitespaces) // ~500 chars
        let text = Array(repeating: para, count: 6).joined(separator: "\n\n") // ~3k chars
        let chunks = Chunker.chunks(of: text, target: 800)
        XCTAssertGreaterThan(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 1200 }, "no chunk should balloon far past target")
        // No content lost.
        let rejoined = chunks.joined(separator: " ")
        XCTAssertTrue(rejoined.contains("word word"))
    }

    func testEmptyTextYieldsNoChunks() {
        XCTAssertTrue(Chunker.chunks(of: "   \n ", target: 800).isEmpty)
    }
}
