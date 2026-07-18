import Foundation

/// The storage seam (spec §18): a minimal async key/value contract the runtime
/// persists through. The in-memory implementation backs tests and early boot;
/// a SQLite-backed implementation conforms to the same protocol later.
protocol KeyValueStore: Sendable {
    func string(forKey key: String) async -> String?
    func set(_ value: String, forKey key: String) async
    func remove(forKey key: String) async
}

/// A process-local, non-durable ``KeyValueStore``.
actor InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: String] = [:]

    func string(forKey key: String) async -> String? { storage[key] }
    func set(_ value: String, forKey key: String) async { storage[key] = value }
    func remove(forKey key: String) async { storage[key] = nil }
}
