import Foundation

/// Where the product hurts (spec §120).
struct FrictionReport: Sendable {
    let slow: [String]
    let confusing: [String]
    let unused: [String]
    let broken: [String]
}

/// Records daily-use friction (spec §120) so the team can fix what actually
/// gets in the way.
actor DogfoodEngine {

    enum FrictionKind { case slow, confusing, unused, broken }

    private var slow: [String] = []
    private var confusing: [String] = []
    private var unused: [String] = []
    private var broken: [String] = []

    func logFriction(_ kind: FrictionKind, _ what: String) {
        switch kind {
        case .slow: slow.append(what)
        case .confusing: confusing.append(what)
        case .unused: unused.append(what)
        case .broken: broken.append(what)
        }
    }

    func report() -> FrictionReport {
        FrictionReport(slow: slow, confusing: confusing, unused: unused, broken: broken)
    }
}
