import XCTest
@testable import Aria

final class DocumentReaderTests: XCTestCase {
    let reader = DocumentReader()
    var tempFiles: [URL] = []

    override func tearDown() {
        super.tearDown()
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles = []
    }

    // MARK: - Helpers

    private func writeTempFile(name: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        tempFiles.append(url)
        return url
    }

    // MARK: - extract()

    func testExtractTxt() async throws {
        let content = "Hello, this is a plain text file."
        let url = try writeTempFile(name: "test-\(UUID().uuidString).txt", content: content)
        let extracted = try await reader.extract(path: url.path)
        XCTAssertEqual(extracted, content)
    }

    func testExtractMarkdown() async throws {
        let content = "# Heading\n\nSome **bold** text."
        let url = try writeTempFile(name: "test-\(UUID().uuidString).md", content: content)
        let extracted = try await reader.extract(path: url.path)
        XCTAssertEqual(extracted, content)
    }

    func testExtractUnsupportedTypeThrows() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("file.xyz")
        // Create empty file so it exists
        FileManager.default.createFile(atPath: url.path, contents: Data())
        tempFiles.append(url)
        do {
            _ = try await reader.extract(path: url.path)
            XCTFail("Expected unsupportedType error")
        } catch let error as DocumentReaderError {
            if case .unsupportedType(let ext) = error {
                XCTAssertEqual(ext, "xyz")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExtractFileNotFoundThrows() async {
        let nonexistentPath = "/tmp/aria-test-nonexistent-\(UUID().uuidString).txt"
        do {
            _ = try await reader.extract(path: nonexistentPath)
            XCTFail("Expected fileNotFound error")
        } catch let error as DocumentReaderError {
            XCTAssertEqual(error, .fileNotFound)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExtractTruncatesAtMaxChars() async throws {
        let content = String(repeating: "x", count: 100)
        let url = try writeTempFile(name: "test-\(UUID().uuidString).txt", content: content)
        let extracted = try await reader.extract(path: url.path, maxChars: 50)
        XCTAssertEqual(extracted.count, 50)
    }

    // Integration test: requires real PDF file on disk
    // func testExtractPDF() async throws { ... }

    // MARK: - summarize()

    func testSummarizeCallsSynthesize() async throws {
        let text = "This is the document text."
        final class Box: @unchecked Sendable { var value = "" }
        let box = Box()
        let summary = try await reader.summarize(text: text, query: nil) { prompt in
            box.value = prompt
            return "Summary result."
        }
        XCTAssertTrue(box.value.contains(text), "Prompt should contain the document text")
        XCTAssertEqual(summary, "Summary result.")
    }

    func testSummarizeWithQueryIncludesQuery() async throws {
        let text = "Document content here."
        let query = "main conclusions"
        final class Box: @unchecked Sendable { var value = "" }
        let box = Box()
        _ = try await reader.summarize(text: text, query: query) { prompt in
            box.value = prompt
            return "Summary."
        }
        XCTAssertTrue(box.value.contains(query), "Prompt should include the query")
        XCTAssertTrue(box.value.contains(text), "Prompt should include the document text")
    }
}
