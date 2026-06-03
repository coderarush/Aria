import XCTest
@testable import Aria

final class DynamicToolTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("friday-tools-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testGeneratedToolCodable() throws {
        let tool = GeneratedTool(name: "scrape_jobs", description: "scrape jobs",
                                 language: .python, code: "print('hi')")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(tool)
        let decoded = try decoder.decode(GeneratedTool.self, from: data)
        // iso8601 drops sub-second precision, so compare fields (not createdAt exactly).
        XCTAssertEqual(decoded.id, tool.id)
        XCTAssertEqual(decoded.name, tool.name)
        XCTAssertEqual(decoded.language, tool.language)
        XCTAssertEqual(decoded.code, tool.code)
        XCTAssertEqual(decoded.source, tool.source)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       tool.createdAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testSlugging() {
        XCTAssertEqual(DynamicToolFactory.slug(from: "Scrape job listings into CSV file now"),
                       "scrape_job_listings_into")
        XCTAssertFalse(DynamicToolFactory.slug(from: "!!!").isEmpty)
    }

    func testSaveLoadDeleteRoundTrip() async {
        let factory = DynamicToolFactory(toolsDir: tempDir())
        let tool = GeneratedTool(name: "t", description: "d", language: .bash, code: "echo hi")
        let saved = await factory.saveTool(tool)
        var loaded = await factory.loadPersistedTools()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, saved.id)

        await factory.recordUsage(saved.id)
        loaded = await factory.loadPersistedTools()
        XCTAssertEqual(loaded.first?.usageCount, 1)

        let deleted = await factory.deleteTool(saved.id)
        XCTAssertTrue(deleted)
        loaded = await factory.loadPersistedTools()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: ScriptRunner (uses real interpreters present on the dev machine)

    func testRunBashEcho() async throws {
        guard ScriptRunner.interpreter(for: .bash) != nil else {
            throw XCTSkip("bash not available")
        }
        let out = try await ScriptRunner().run(code: "echo friday-ok", language: .bash, timeout: 10)
        XCTAssertTrue(out.success)
        XCTAssertTrue(out.stdout.contains("friday-ok"))
    }

    func testRunBashNonZeroExit() async throws {
        let out = try await ScriptRunner().run(code: "exit 3", language: .bash, timeout: 10)
        XCTAssertFalse(out.success)
        XCTAssertEqual(out.exitCode, 3)
    }

    func testTimeoutThrows() async {
        do {
            _ = try await ScriptRunner().run(code: "sleep 5", language: .bash, timeout: 1)
            XCTFail("expected timeout")
        } catch let error as ToolError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDynamicSettingsDefaults() {
        let suite = UserDefaults(suiteName: "friday-test-\(UUID().uuidString)")!
        let s = DynamicToolSettings.load(suite)
        XCTAssertTrue(s.allowCodeExecution)
        XCTAssertFalse(s.showCodeBeforeRun)
        XCTAssertTrue(s.askBeforeSaving)
        XCTAssertFalse(s.syncCommunityTools)
    }
}
