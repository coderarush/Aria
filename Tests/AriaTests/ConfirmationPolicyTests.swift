import XCTest
@testable import Aria

final class ConfirmationPolicyTests: XCTestCase {

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "aria-confirm-\(UUID().uuidString)")!
    }

    func testDefaultsToConfirmingDestructiveActions() {
        // Safe by default: an unset flag means we DO confirm send/pay/delete.
        XCTAssertTrue(ConfirmationPolicy.confirmsDestructive(suite()))
    }

    func testExplicitOptInConfirms() {
        let d = suite()
        d.set(true, forKey: "app.confirmDestructive")
        XCTAssertTrue(ConfirmationPolicy.confirmsDestructive(d))
    }

    func testExplicitOptOutRestoresZeroFriction() {
        // Users who shipped on auto-approve can turn confirmation back off.
        let d = suite()
        d.set(false, forKey: "app.confirmDestructive")
        XCTAssertFalse(ConfirmationPolicy.confirmsDestructive(d))
    }
}
