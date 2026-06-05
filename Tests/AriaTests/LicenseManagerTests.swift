import XCTest
@testable import Aria

final class LicenseManagerTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testLicensedAlwaysLicensed() {
        let s = LicenseManager.computeStatus(licensed: true, firstRun: Date(timeIntervalSince1970: 0),
                                             now: Date(timeIntervalSince1970: 999 * day), trialDays: 7)
        XCTAssertEqual(s, .licensed)
    }

    func testTrialCountsDown() {
        let s = LicenseManager.computeStatus(licensed: false, firstRun: Date(timeIntervalSince1970: 0),
                                             now: Date(timeIntervalSince1970: 2 * day), trialDays: 7)
        XCTAssertEqual(s, .trial(daysLeft: 5))
    }

    func testTrialExpires() {
        let s = LicenseManager.computeStatus(licensed: false, firstRun: Date(timeIntervalSince1970: 0),
                                             now: Date(timeIntervalSince1970: 8 * day), trialDays: 7)
        XCTAssertEqual(s, .expired)
    }

    func testVendorParsers() {
        XCTAssertTrue(LicenseManager.parseLemonSqueezy(Data(#"{"valid":true}"#.utf8)))
        XCTAssertFalse(LicenseManager.parseLemonSqueezy(Data(#"{"valid":false}"#.utf8)))
        XCTAssertTrue(LicenseManager.parseGumroad(Data(#"{"success":true,"purchase":{}}"#.utf8)))
        XCTAssertFalse(LicenseManager.parseGumroad(Data("garbage".utf8)))
    }
}
