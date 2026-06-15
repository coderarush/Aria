import XCTest
@testable import Aria

// MARK: - Pure Drive URL / query builders

final class DriveURLBuilderTests: XCTestCase {

    func testSearchURLWrapsQueryInNameContainsAndExcludesTrashed() throws {
        let url = GoogleConnector.driveSearchURL(query: "launch plan", maxResults: 7)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "/drive/v3/files")
        let items = try XCTUnwrap(comps.queryItems)
        let q = try XCTUnwrap(items.first { $0.name == "q" }?.value)
        XCTAssertEqual(q, "name contains 'launch plan' and trashed = false")
        XCTAssertEqual(items.first { $0.name == "pageSize" }?.value, "7")
        XCTAssertEqual(items.first { $0.name == "fields" }?.value, "files(id,name,mimeType)")
    }

    func testSearchURLEscapesSingleQuoteInQuery() throws {
        let url = GoogleConnector.driveSearchURL(query: "Bob's notes")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let q = try XCTUnwrap(comps.queryItems?.first { $0.name == "q" }?.value)
        // The user quote is backslash-escaped so it can't break out of Drive's
        // query-string literal.
        XCTAssertEqual(q, "name contains 'Bob\\'s notes' and trashed = false")
    }

    func testExportURLTargetsExportPathWithMimeType() throws {
        let url = GoogleConnector.driveExportURL(id: "abc123", mimeType: "text/plain")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "/drive/v3/files/abc123/export")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "mimeType" }?.value, "text/plain")
    }

    func testMediaURLUsesAltMedia() throws {
        let url = GoogleConnector.driveMediaURL(id: "abc123")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "/drive/v3/files/abc123")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "alt" }?.value, "media")
    }

    func testFileIDsArePathPercentEncoded() {
        // A pathological id with a space must be percent-encoded (mirrors the
        // existing draftDeleteURL/eventDeleteURL .urlPathAllowed convention — a
        // slash is a legal path char and is intentionally left intact).
        let url = GoogleConnector.driveMetadataURL(id: "a b")
        XCTAssertTrue(url.absoluteString.contains("/files/a%20b"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://www.googleapis.com/drive/v3/files/"))
    }

    func testUploadURLUsesUploadPathAndMultipart() throws {
        let url = GoogleConnector.driveUploadURL()
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "/upload/drive/v3/files")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "uploadType" }?.value, "multipart")
    }
}

// MARK: - Drive MIME-type classification

final class DriveMimeTypeTests: XCTestCase {

    func testGoogleNativeDocsAreExportable() {
        XCTAssertTrue(GoogleConnector.isGoogleNativeTextDoc("application/vnd.google-apps.document"))
        XCTAssertTrue(GoogleConnector.isGoogleNativeTextDoc("application/vnd.google-apps.spreadsheet"))
        XCTAssertTrue(GoogleConnector.isGoogleNativeTextDoc("application/vnd.google-apps.presentation"))
        XCTAssertFalse(GoogleConnector.isGoogleNativeTextDoc("application/vnd.google-apps.folder"))
        XCTAssertFalse(GoogleConnector.isGoogleNativeTextDoc("application/pdf"))
    }

    func testReadableMediaTypes() {
        XCTAssertTrue(GoogleConnector.isReadableMediaType("text/plain"))
        XCTAssertTrue(GoogleConnector.isReadableMediaType("text/markdown"))
        XCTAssertTrue(GoogleConnector.isReadableMediaType("application/json"))
        XCTAssertFalse(GoogleConnector.isReadableMediaType("image/png"))
        XCTAssertFalse(GoogleConnector.isReadableMediaType("application/pdf"))
    }
}

// MARK: - Pure Drive multipart body

final class DriveMultipartBodyTests: XCTestCase {

    func testMultipartBodyHasMetadataAndMediaPartsWithBoundary() throws {
        let (data, contentType) = GoogleConnector.driveMultipartBody(
            name: "Launch.txt", content: "ship it", boundary: "B")
        XCTAssertEqual(contentType, "multipart/related; boundary=B")
        let body = String(decoding: data, as: UTF8.self)
        // Two parts delimited by the boundary, closing delimiter present.
        XCTAssertTrue(body.contains("--B\r\nContent-Type: application/json; charset=UTF-8"))
        XCTAssertTrue(body.contains("Content-Type: text/plain; charset=UTF-8"))
        XCTAssertTrue(body.contains("ship it"))
        XCTAssertTrue(body.contains("--B--"))
        // The metadata part is valid JSON carrying the name.
        XCTAssertTrue(body.contains("\"name\":\"Launch.txt\""))
    }
}

// MARK: - Pure Drive response parsers

final class DriveParseTests: XCTestCase {

    func testParsesFileList() {
        let json = #"{"files":[{"id":"1","name":"Plan","mimeType":"application/vnd.google-apps.document"},{"id":"2","name":"Notes.txt","mimeType":"text/plain"}]}"#
        let files = GoogleConnector.parseDriveFileList(Data(json.utf8))
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0], GoogleConnector.DriveFile(
            id: "1", name: "Plan", mimeType: "application/vnd.google-apps.document"))
        XCTAssertEqual(files[1].name, "Notes.txt")
    }

    func testFileListSkipsRowsMissingIDOrName() {
        let json = #"{"files":[{"name":"no id"},{"id":"x"},{"id":"ok","name":"Good"}]}"#
        let files = GoogleConnector.parseDriveFileList(Data(json.utf8))
        XCTAssertEqual(files.map(\.id), ["ok"])
    }

    func testParsesFileMetaWithDefaults() {
        let (name, mime) = GoogleConnector.parseDriveFileMeta(
            Data(#"{"name":"Doc","mimeType":"text/plain"}"#.utf8))
        XCTAssertEqual(name, "Doc")
        XCTAssertEqual(mime, "text/plain")
        // Missing fields fall back, never crash.
        let (n2, m2) = GoogleConnector.parseDriveFileMeta(Data("{}".utf8))
        XCTAssertEqual(n2, "(untitled)")
        XCTAssertEqual(m2, "")
    }

    func testParsesCreatedFileID() {
        XCTAssertEqual(
            GoogleConnector.parseDriveFileID(Data(#"{"id":"new_99","name":"x"}"#.utf8)), "new_99")
        XCTAssertNil(GoogleConnector.parseDriveFileID(Data("not json".utf8)))
        XCTAssertNil(GoogleConnector.parseDriveFileID(Data("{}".utf8)))
    }

    func testFormatDriveReadHandlesTextEmptyAndUnreadable() {
        let text = GoogleConnector.formatDriveRead(.text(name: "A", content: "hello"))
        XCTAssertTrue(text.contains("A:"))
        XCTAssertTrue(text.contains("hello"))
        let empty = GoogleConnector.formatDriveRead(.text(name: "A", content: "   "))
        XCTAssertTrue(empty.contains("empty"))
        let bad = GoogleConnector.formatDriveRead(.unreadable(name: "pic.png", mimeType: "image/png"))
        XCTAssertTrue(bad.lowercased().contains("can't read"))
        XCTAssertTrue(bad.contains("image/png"))
    }

    func testFormatDriveFilesEmptyAndPopulated() {
        XCTAssertTrue(GoogleConnector.formatDriveFiles([]).contains("No matching"))
        let block = GoogleConnector.formatDriveFiles(
            [GoogleConnector.DriveFile(id: "1", name: "Plan", mimeType: "text/plain")])
        XCTAssertTrue(block.contains("Plan"))
        XCTAssertTrue(block.contains("id: 1"))
    }
}

// MARK: - Not-connected tool behavior (no network, no token)

final class DriveToolNotConnectedTests: XCTestCase {

    /// A ConnectorStore backed by an empty token store → validAccessToken == nil.
    private func emptyStore() -> ConnectorStore {
        ConnectorStore(
            tokenStore: ConnectorTokenStore(read: { _ in nil }, write: { _, _ in }, remove: { _ in }),
            authorize: { _, _ in
                OAuth2.TokenResponse(accessToken: "", refreshToken: nil, expiresIn: 0,
                                     scopes: [], tokenType: "Bearer")
            })
    }

    func testDriveSearchNotConnectedReturnsCleanMessage() async throws {
        let tool = DriveSearchTool(store: emptyStore())
        let result = try await tool.run(input: ["query": "plan"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Drive"))
    }

    func testDriveSearchMissingQueryThrowsBeforeNetwork() async {
        let tool = DriveSearchTool(store: emptyStore())
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput for empty query")
        } catch ToolError.missingInput(let field) {
            XCTAssertEqual(field, "query")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDriveReadNotConnectedReturnsCleanMessage() async throws {
        let tool = DriveReadTool(store: emptyStore())
        let result = try await tool.run(input: ["file_id": "abc"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Drive"))
    }

    func testDriveReadMissingBothIdentifiersThrowsBeforeNetwork() async {
        let tool = DriveReadTool(store: emptyStore())
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput when neither file_id nor name given")
        } catch ToolError.missingInput {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDriveCreateNotConnectedReturnsCleanMessage() async throws {
        let tool = DriveCreateTool(store: emptyStore())
        let result = try await tool.run(input: ["name": "Notes.txt", "content": "hi"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("connect"))
        XCTAssertTrue(result.output.contains("Drive"))
    }

    func testDriveCreateMissingFieldsThrowBeforeNetwork() async {
        let tool = DriveCreateTool(store: emptyStore())
        for missing in [["content": "x"], ["name": "n"]] {
            do {
                _ = try await tool.run(input: missing)
                XCTFail("expected missingInput for \(missing)")
            } catch is ToolError {
                // expected
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Safety classification of the Drive tools

final class DriveToolSafetyTests: XCTestCase {

    func testDriveSearchIsRoutine() {
        XCTAssertEqual(
            Safety.importance(tool: "drive_search",
                              input: ["query": "delete the old plan"],
                              summary: "search drive"),
            .routine)
        XCTAssertTrue(Safety.importance(tool: "drive_search", input: [:], summary: "") == .routine)
        XCTAssertFalse(DriveSearchTool().isDestructive)
    }

    func testDriveReadIsRoutine() {
        XCTAssertEqual(
            Safety.importance(tool: "drive_read",
                              input: ["name": "send the report"],
                              summary: "read drive file"),
            .routine)
        XCTAssertFalse(DriveReadTool().isDestructive)
    }

    func testDriveCreateDoesNotGate() {
        // Reversible-ish (can be trashed) → routine, NOT importantIrreversible,
        // even with a danger word in the file name or content.
        XCTAssertEqual(
            Safety.importance(tool: "drive_create",
                              input: ["name": "send-off.txt", "content": "delete everything"],
                              summary: "create a drive file"),
            .routine)
        XCTAssertNotEqual(
            Safety.importance(tool: "drive_create",
                              input: ["name": "n", "content": "c"],
                              summary: "create a drive file"),
            .importantIrreversible)
        XCTAssertFalse(Safety.importantTools.contains("drive_create"))
        XCTAssertFalse(DriveCreateTool().isDestructive)
    }
}
