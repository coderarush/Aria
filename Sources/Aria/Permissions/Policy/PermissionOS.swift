import Foundation

/// What an action is permitted to do (spec §54). Ordered as a ladder: a higher
/// grant covers everything below it.
enum PermissionType: String, Sendable, Comparable, CaseIterable {
    case observe, prepare, modify, execute, autonomous
    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    static func < (lhs: PermissionType, rhs: PermissionType) -> Bool { lhs.rank < rhs.rank }
}

/// How long a grant lasts (spec §54).
enum PermissionScope: String, Sendable { case once, session, objective, persistent }

/// A single permission grant.
struct PermissionGrant: Identifiable, Sendable {
    let id: UUID
    var type: PermissionType
    var scope: PermissionScope
    var subject: String
    var objectiveID: UUID?
    var grantedAt: Date
    var expiresAt: Date?
    var revoked: Bool
}

/// Append-only record of every consent decision (spec §54 ConsentLedger).
actor ConsentLedger {
    struct Entry: Sendable {
        let who: String
        let what: String
        let when: Date
        let why: String
        let result: String
    }

    private(set) var entries: [Entry] = []

    func record(who: String, what: String, why: String, result: String, when: Date = Date()) {
        entries.append(Entry(who: who, what: what, when: when, why: why, result: result))
    }

    var all: [Entry] { entries }
}

/// Explicit, recoverable, auditable permissions (spec §54). Grants form a
/// ladder; higher types cover lower ones; `.once` grants are consumed on use.
actor PermissionOS {

    private var grants: [PermissionGrant] = []
    private let ledger: ConsentLedger

    init(ledger: ConsentLedger = ConsentLedger()) {
        self.ledger = ledger
    }

    @discardableResult
    func grant(type: PermissionType,
               scope: PermissionScope,
               subject: String,
               objectiveID: UUID?,
               expiresAt: Date?,
               why: String) async -> PermissionGrant {
        let grant = PermissionGrant(id: UUID(), type: type, scope: scope, subject: subject,
                                    objectiveID: objectiveID, grantedAt: Date(),
                                    expiresAt: expiresAt, revoked: false)
        grants.append(grant)
        await ledger.record(who: "user", what: subject, why: why, result: "granted")
        return grant
    }

    func revoke(_ id: UUID) async {
        guard let index = grants.firstIndex(where: { $0.id == id }) else { return }
        grants[index].revoked = true
        await ledger.record(who: "user", what: grants[index].subject, why: "revoked", result: "revoked")
    }

    /// Whether an active grant covers the requested type+subject as of `date`.
    /// Consumes `.once` grants on a successful check.
    func isAllowed(type: PermissionType, subject: String, asOf date: Date) -> Bool {
        guard let index = grants.firstIndex(where: { grant in
            !grant.revoked
                && grant.subject == subject
                && grant.type >= type
                && (grant.expiresAt.map { $0 > date } ?? true)
        }) else { return false }

        if grants[index].scope == .once { grants[index].revoked = true }
        return true
    }
}
