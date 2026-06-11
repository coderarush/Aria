import XCTest
@testable import Aria

/// V11 P5 — Project Memory 2.0: project tags on work entries, inference from
/// task phrasing, and project-scoped recall ("continue my Verdai work").
final class ProjectMemoryTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString).json")
    }

    private func day(_ d: Int, hour: Int = 10) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = d; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    // MARK: ProjectTagger inference

    func testInfersProjectFromMyXWork() {
        XCTAssertEqual(ProjectTagger.infer(from: "continue my Verdai work"), "Verdai")
        XCTAssertEqual(ProjectTagger.infer(from: "continue my verdai work"), "Verdai")
    }

    func testInfersProjectFromXProject() {
        XCTAssertEqual(ProjectTagger.infer(from: "summarize the Atlas project status"), "Atlas")
    }

    func testInfersProjectFromWorkOnX() {
        XCTAssertEqual(ProjectTagger.infer(from: "work on Aria"), "Aria")
    }

    func testNoInferenceForPlainTasks() {
        XCTAssertNil(ProjectTagger.infer(from: "organize my downloads folder"))
        XCTAssertNil(ProjectTagger.infer(from: "what time is it"))
        XCTAssertNil(ProjectTagger.infer(from: "brief me"))
    }

    func testStopwordsNeverBecomeProjects() {
        XCTAssertNil(ProjectTagger.infer(from: "continue my own work"))
        XCTAssertNil(ProjectTagger.infer(from: "work on it"))
    }

    // MARK: journal project storage + queries

    func testRecordStoresExplicitProject() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "draft pitch deck", outcome: "6 slides", ok: true,
                       project: "Verdai", at: day(9))
        let hits = await j.entries(project: "Verdai")
        XCTAssertEqual(hits.map(\.title), ["draft pitch deck"])
    }

    func testRecordInfersProjectFromTitle() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "continue my Verdai work", outcome: "resumed", ok: true, at: day(9))
        let hits = await j.entries(project: "Verdai")
        XCTAssertEqual(hits.count, 1)
    }

    func testProjectFilterIsCaseInsensitive() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "t", outcome: "", ok: true, project: "Verdai", at: day(9))
        let hits = await j.entries(project: "verdai")
        XCTAssertEqual(hits.count, 1)
    }

    func testProjectsListsDistinctNewestFirst() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "a", outcome: "", ok: true, project: "Atlas", at: day(8))
        await j.record(kind: .task, title: "b", outcome: "", ok: true, project: "Verdai", at: day(9))
        await j.record(kind: .task, title: "c", outcome: "", ok: true, project: "Atlas", at: day(10))
        let projects = await j.projects()
        XCTAssertEqual(projects, ["Atlas", "Verdai"])
    }

    func testProjectDigestSummarizesScopedWork() async {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "deck", outcome: "6 slides drafted", ok: true, project: "Verdai", at: day(9))
        await j.record(kind: .task, title: "unrelated", outcome: "noise", ok: true, at: day(9, hour: 12))
        let digest = await j.projectDigest("Verdai")
        XCTAssertTrue(digest.contains("deck"))
        XCTAssertFalse(digest.contains("unrelated"))
    }

    // MARK: backward compatibility — old journal.json has no project field

    func testDecodesLegacyEntriesWithoutProject() async {
        let url = tempURL()
        let legacy = #"[{"date":1780000000,"kind":"task","title":"old task","outcome":"done","ok":true}]"#
        try? Data(legacy.utf8).write(to: url)
        let j = WorkJournal(fileURL: url)
        let all = await j.entries(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(all.map(\.title), ["old task"])
        XCTAssertNil(all.first?.project)
    }

    // MARK: recall tool project param

    func testRecallToolAnswersProjectQuery() async throws {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "deck", outcome: "6 slides drafted", ok: true,
                       project: "Verdai", at: day(9))
        let tool = RecallWorkTool(journal: j, now: { self.day(10) })
        let result = try await tool.run(input: ["project": "Verdai"])
        XCTAssertTrue(result.output.contains("deck"))
        XCTAssertTrue(result.output.contains("Verdai"))
    }

    func testRecallToolListsProjectsWhenAskedForUnknown() async throws {
        let j = WorkJournal(fileURL: tempURL())
        await j.record(kind: .task, title: "a", outcome: "", ok: true, project: "Atlas", at: day(9))
        let tool = RecallWorkTool(journal: j, now: { self.day(10) })
        let result = try await tool.run(input: ["project": "Nonexistent"])
        XCTAssertTrue(result.output.contains("Atlas"))
    }
}
