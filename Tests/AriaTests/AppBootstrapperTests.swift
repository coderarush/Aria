import XCTest
@testable import Aria

final class AppBootstrapperTests: XCTestCase {

    func testInitializeBringsRuntimeToIdle() async {
        let boot = AppBootstrapper()
        let runtime = await boot.initialize()
        let state = await runtime.state
        XCTAssertEqual(state, .idle)
    }

    func testVerifyFailsBeforeInitialize() async {
        let boot = AppBootstrapper()
        let ok = await boot.verify()
        XCTAssertFalse(ok)
    }

    func testVerifyPassesAfterInitialize() async {
        let boot = AppBootstrapper()
        _ = await boot.initialize()
        let ok = await boot.verify()
        XCTAssertTrue(ok)
    }

    func testInitializeExposesSharedEventBus() async {
        let boot = AppBootstrapper()
        let runtime = await boot.initialize()
        let bus = await boot.eventBus
        XCTAssertNotNil(bus)
        // Runtime start emitted a state-change onto the shared bus.
        let replay = await bus?.replay() ?? []
        XCTAssertTrue(replay.contains { $0.kind == .runtimeStateChanged })
        _ = runtime
    }
}
