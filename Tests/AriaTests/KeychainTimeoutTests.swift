import XCTest
@testable import Aria

final class KeychainTimeoutTests: XCTestCase {

    func testFastReadPassesThrough() {
        let v = KeychainManager.withTimeout(0.5, label: "test") { "secret" }
        XCTAssertEqual(v, "secret")
    }

    func testBlockedReadReturnsNilInsteadOfHanging() {
        let started = Date()
        let v: String? = KeychainManager.withTimeout(0.3, label: "test") {
            Thread.sleep(forTimeInterval: 10)   // simulated securityd ACL park
            return "too late"
        }
        XCTAssertNil(v, "a blocked keychain read must yield nil, never hang the caller")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
    }

    func testSecondCallAfterTimeoutStillWorks() {
        _ = KeychainManager.withTimeout(0.2, label: "test") { Thread.sleep(forTimeInterval: 5); return "x" }
        let v = KeychainManager.withTimeout(0.5, label: "test") { "fresh" }
        XCTAssertEqual(v, "fresh")
    }
}
