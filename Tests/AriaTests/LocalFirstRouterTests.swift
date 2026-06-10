import XCTest
@testable import Aria

final class LocalFirstRouterTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "lfr-\(UUID().uuidString)")!
    }

    func testDisabledTogglesGoCloudWithoutProbing() async {
        let d = defaults()
        d.set(false, forKey: "app.localFirst")
        var probed = false
        let router = LocalFirstRouter(defaults: d,
                                      makeProvider: { _ in DeterministicProvider(script: [:], fallback: "x") },
                                      availability: { probed = true; return true })
        let decision = await router.decide(taskClass: .planning)
        XCTAssertEqual(decision.tier, .cloud)
        XCTAssertFalse(probed, "must not probe the local server when the toggle is off")
    }

    func testEnabledEligibleAndAvailableGoesLocal() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(defaults: d,
                                      makeProvider: { _ in DeterministicProvider(script: [:], fallback: "x") },
                                      availability: { true })
        let decision = await router.decide(taskClass: .planning)
        XCTAssertEqual(decision.tier, .local)
    }

    func testEnabledButDeadServerGoesCloud() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(defaults: d,
                                      makeProvider: { _ in DeterministicProvider(script: [:], fallback: "x") },
                                      availability: { false })
        let decision = await router.decide(taskClass: .planning)
        XCTAssertEqual(decision.tier, .cloud)
        XCTAssertTrue(decision.reason.contains("unreachable"))
    }

    func testTryLocalReturnsTextOnSuccess() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "local says hi") },
            availability: { true })
        let out = await router.tryLocal(prompt: "plan something", temperature: 0.2)
        XCTAssertEqual(out, "local says hi")
    }

    func testTryLocalReturnsNilOnEmptyOutput() async {
        let d = defaults()
        d.set(true, forKey: "app.localFirst")
        let router = LocalFirstRouter(
            defaults: d,
            makeProvider: { _ in DeterministicProvider(script: [:], fallback: "") },
            availability: { true })
        let out = await router.tryLocal(prompt: "plan", temperature: 0.2)
        XCTAssertNil(out, "empty local output must fall through to cloud")
    }
}
