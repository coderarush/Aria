import Foundation

/// Verifies and stores the app's license. Supports Lemon Squeezy and Gumroad license-
/// key verification (set `vendor`/`productID` at release). Once activated, the key is
/// stored so the app keeps working offline. A short trial lets people try before buying.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum Status: Equatable { case licensed, trial(daysLeft: Int), expired }
    enum Vendor { case lemonSqueezy, gumroad }

    @Published private(set) var status: Status = .trial(daysLeft: 7)

    /// Configure when the storefront is set up.
    var vendor: Vendor = .lemonSqueezy
    var productID: String = ""        // Gumroad product id (verify endpoint)
    let trialDays = 7

    private let defaults = UserDefaults.standard

    init() { refresh() }

    var isLicensed: Bool { status == .licensed }
    /// True if the app may be used right now (licensed or still in trial).
    var canUse: Bool { if case .expired = status { return false }; return true }

    func refresh() {
        let licensed = defaults.string(forKey: K.key) != nil && defaults.bool(forKey: K.valid)
        status = Self.computeStatus(licensed: licensed, firstRun: firstRunDate(), now: Date(), trialDays: trialDays)
    }

    /// Validate a key with the vendor; on success store it (works offline afterward).
    func activate(key: String) async -> (ok: Bool, message: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "Enter your license key.") }
        do {
            let valid = try await verify(key: trimmed)
            guard valid else { return (false, "That key didn't validate. Double-check it and try again.") }
            defaults.set(trimmed, forKey: K.key)
            defaults.set(true, forKey: K.valid)
            refresh()
            return (true, "Activated. Thank you for buying Aria.")
        } catch {
            return (false, "Couldn't reach the license server. Check your connection and try again.")
        }
    }

    func deactivate() {
        defaults.removeObject(forKey: K.key)
        defaults.set(false, forKey: K.valid)
        refresh()
    }

    // MARK: pure logic (testable)

    nonisolated static func computeStatus(licensed: Bool, firstRun: Date, now: Date, trialDays: Int) -> Status {
        if licensed { return .licensed }
        let used = Int(now.timeIntervalSince(firstRun) / 86_400)
        let left = trialDays - used
        return left > 0 ? .trial(daysLeft: left) : .expired
    }

    nonisolated static func parseLemonSqueezy(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["valid"] as? Bool ?? false
    }
    nonisolated static func parseGumroad(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["success"] as? Bool ?? false
    }

    // MARK: vendor calls

    private func verify(key: String) async throws -> Bool {
        switch vendor {
        case .lemonSqueezy:
            var req = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "license_key=\(key)".data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: req)
            return Self.parseLemonSqueezy(data)
        case .gumroad:
            var req = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "product_id=\(productID)&license_key=\(key)"
            req.httpBody = body.data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: req)
            return Self.parseGumroad(data)
        }
    }

    private func firstRunDate() -> Date {
        if let d = defaults.object(forKey: K.firstRun) as? Date { return d }
        let now = Date(); defaults.set(now, forKey: K.firstRun); return now
    }

    private enum K {
        static let key = "license.key"
        static let valid = "license.valid"
        static let firstRun = "license.firstRun"
    }
}
