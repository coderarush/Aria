import Foundation

/// Planning horizons (spec §100).
enum Horizon: String, Sendable, CaseIterable { case today, week, month, quarter, project }

/// Plans across long horizons (spec §100): plan/rebalance/continue/compress.
actor HorizonEngine {

    private var items: [Horizon: [String]] = [:]

    func plan(_ title: String, at horizon: Horizon) {
        items[horizon, default: []].append(title)
    }

    func items(at horizon: Horizon) -> [String] { items[horizon] ?? [] }

    /// Move every item from one horizon to another.
    func rebalance(from: Horizon, to: Horizon) {
        let moving = items[from] ?? []
        items[to, default: []].append(contentsOf: moving)
        items[from] = []
    }

    /// Collapse duplicates within a horizon (preserving order).
    func compress(_ horizon: Horizon) {
        var seen: Set<String> = []
        items[horizon] = (items[horizon] ?? []).filter { seen.insert($0).inserted }
    }
}
