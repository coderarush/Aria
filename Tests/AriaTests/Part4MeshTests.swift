import XCTest
@testable import Aria

final class Part4MeshTests: XCTestCase {

    // MARK: - DeviceMesh (§77)

    func testDefaultRolesPerDevice() {
        XCTAssertEqual(DeviceMesh.defaultRole(for: .desktop), .execution)
        XCTAssertEqual(DeviceMesh.defaultRole(for: .phone), .control)
        XCTAssertEqual(DeviceMesh.defaultRole(for: .watch), .awareness)
        XCTAssertEqual(DeviceMesh.defaultRole(for: .glass), .presence)
    }

    func testDiscoverConnectDisconnect() async {
        let mesh = DeviceMesh()
        await mesh.discover(.desktop, role: .execution)
        await mesh.connect(.desktop)
        var connected = await mesh.connected()
        XCTAssertEqual(connected.map(\.kind), [.desktop])

        await mesh.disconnect(.desktop)
        connected = await mesh.connected()
        XCTAssertTrue(connected.isEmpty)
    }

    // MARK: - ContextHandoff (§78)

    func testSendThenReceiveResumesAndClears() async {
        let handoff = ContextHandoff()
        let objective = UUID()
        let bundle = HandoffBundle(objectiveID: objective, memory: ["m1"],
                                   attention: "flow", status: "executing", artifacts: ["a"])
        await handoff.send(bundle, to: .phone)

        let received = await handoff.receive(on: .phone)
        XCTAssertEqual(received?.objectiveID, objective)
        XCTAssertEqual(received?.memory, ["m1"])

        let again = await handoff.receive(on: .phone)
        XCTAssertNil(again)   // consumed
    }

    func testReceiveOnWrongDeviceIsNil() async {
        let handoff = ContextHandoff()
        await handoff.send(HandoffBundle(objectiveID: nil, memory: [], attention: "",
                                         status: "", artifacts: []), to: .glass)
        let received = await handoff.receive(on: .watch)
        XCTAssertNil(received)
    }
}
