import XCTest
@testable import Aria

@MainActor
private final class FakeSurface: PresenterSurface {
    var glowing = false
    var spoken: [String] = []
    var ranCommands: [String] = []
    var approved: [UUID] = []

    func showGlow() { glowing = true }
    func clearGlow() { glowing = false }
    func speak(_ line: String) { spoken.append(line) }
    func runCommand(_ command: String) async { ranCommands.append(command) }
    func approvePattern(_ id: UUID) async { approved.append(id) }
}

@MainActor
final class SuggestionPresenterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func sugg(action: SuggestionAction) -> Suggestion {
        Suggestion(source: .routine, spokenLine: "Open Slack?", action: action,
                   confidence: 0.7, urgency: .ambient, createdAt: now,
                   expiry: now.addingTimeInterval(600), dedupeKey: "routine:x")
    }

    private func makePresenter(_ surface: FakeSurface) -> (SuggestionPresenter, () -> [(SuggestionOutcome, String)]) {
        var outcomes: [(SuggestionOutcome, String)] = []
        let p = SuggestionPresenter(surface: surface) { outcome, s in
            outcomes.append((outcome, s.dedupeKey))
        }
        return (p, { outcomes })
    }

    func testPresentShowsSilentGlowAndDoesNotSpeak() {
        let surface = FakeSurface()
        let (presenter, _) = makePresenter(surface)
        presenter.present(sugg(action: .acknowledge))
        XCTAssertTrue(surface.glowing)
        XCTAssertTrue(surface.spoken.isEmpty)
        XCTAssertNotNil(presenter.pending)
    }

    func testRevealSpeaksOnce() {
        let surface = FakeSurface()
        let (presenter, _) = makePresenter(surface)
        presenter.present(sugg(action: .acknowledge))
        presenter.reveal()
        presenter.reveal()
        XCTAssertEqual(surface.spoken, ["Open Slack?"])
    }

    func testAcceptRunsCommandAndClears() async {
        let surface = FakeSurface()
        let (presenter, outcomes) = makePresenter(surface)
        presenter.present(sugg(action: .runCommand("open slack")))
        await presenter.accept(now: now)
        XCTAssertEqual(surface.ranCommands, ["open slack"])
        XCTAssertFalse(surface.glowing)
        XCTAssertNil(presenter.pending)
        XCTAssertEqual(outcomes().map(\.0), [.accepted])
    }

    func testAcceptOfferAutomationApprovesPattern() async {
        let id = UUID()
        let surface = FakeSurface()
        let (presenter, _) = makePresenter(surface)
        presenter.present(sugg(action: .offerAutomation(patternID: id)))
        await presenter.accept(now: now)
        XCTAssertEqual(surface.approved, [id])
    }

    func testDismissRecordsAndClears() {
        let surface = FakeSurface()
        let (presenter, outcomes) = makePresenter(surface)
        presenter.present(sugg(action: .acknowledge))
        presenter.dismiss(now: now)
        XCTAssertFalse(surface.glowing)
        XCTAssertNil(presenter.pending)
        XCTAssertEqual(outcomes().map(\.0), [.dismissed])
    }

    func testExpireRecordsExpiredOutcome() {
        let surface = FakeSurface()
        let (presenter, outcomes) = makePresenter(surface)
        presenter.present(sugg(action: .acknowledge))
        presenter.expire(now: now)
        XCTAssertEqual(outcomes().map(\.0), [.expired])
        XCTAssertFalse(surface.glowing)
    }
}
