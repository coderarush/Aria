import XCTest
@testable import Aria

final class Part3PermissionTrustTests: XCTestCase {

    // MARK: - PermissionOS (§54)

    func testGrantThenAllowed() async {
        let perms = PermissionOS()
        _ = await perms.grant(type: .execute, scope: .session, subject: "gmail.send",
                              objectiveID: nil, expiresAt: nil, why: "user asked")
        let allowed = await perms.isAllowed(type: .execute, subject: "gmail.send",
                                            asOf: Date())
        XCTAssertTrue(allowed)
    }

    func testHigherGrantCoversLowerType() async {
        let perms = PermissionOS()
        _ = await perms.grant(type: .execute, scope: .session, subject: "files",
                              objectiveID: nil, expiresAt: nil, why: "x")
        // execute >= modify, so modify is covered
        let allowed = await perms.isAllowed(type: .modify, subject: "files", asOf: Date())
        XCTAssertTrue(allowed)
    }

    func testRevokeRemovesPermission() async {
        let perms = PermissionOS()
        let grant = await perms.grant(type: .execute, scope: .session, subject: "slack",
                                      objectiveID: nil, expiresAt: nil, why: "x")
        await perms.revoke(grant.id)
        let allowed = await perms.isAllowed(type: .execute, subject: "slack", asOf: Date())
        XCTAssertFalse(allowed)
    }

    func testExpiredGrantNotAllowed() async {
        let perms = PermissionOS()
        _ = await perms.grant(type: .execute, scope: .once, subject: "calendar",
                              objectiveID: nil,
                              expiresAt: Date(timeIntervalSince1970: 100), why: "x")
        let allowed = await perms.isAllowed(type: .execute, subject: "calendar",
                                            asOf: Date(timeIntervalSince1970: 200))
        XCTAssertFalse(allowed)
    }

    func testGrantWritesToConsentLedger() async {
        let ledger = ConsentLedger()
        let perms = PermissionOS(ledger: ledger)
        _ = await perms.grant(type: .modify, scope: .objective, subject: "notion",
                              objectiveID: nil, expiresAt: nil, why: "append notes")
        let entries = await ledger.all
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.what, "notion")
        XCTAssertEqual(entries.first?.why, "append notes")
    }

    // MARK: - TrustEngine (§55)

    func testNoSignalsIsNeutral() async {
        let trust = TrustEngine()
        let confidence = await trust.confidence()
        XCTAssertEqual(confidence, 0.5, accuracy: 1e-9)
    }

    func testStrongSignalsRaiseConfidence() async {
        let trust = TrustEngine()
        for _ in 0..<5 { await trust.recordVerification(passed: true) }
        for _ in 0..<5 { await trust.recordTool(success: true) }
        let confidence = await trust.confidence()
        XCTAssertGreaterThan(confidence, 0.9)
    }

    func testCorrectionsLowerConfidence() async {
        let trust = TrustEngine()
        for _ in 0..<5 { await trust.recordVerification(passed: true) }
        for _ in 0..<5 { await trust.recordTool(success: true) }
        await trust.recordCorrection()
        await trust.recordCorrection()
        let confidence = await trust.confidence()
        XCTAssertEqual(confidence, 0.8, accuracy: 1e-9)
    }
}
