import Foundation
import Security

/// Stores secrets (Gemini API key) in the macOS Keychain. No plaintext on disk.
enum KeychainManager {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case dataEncodingFailed
    }

    private static let service = "com.aria.agent"

    // Successful reads are cached for the process lifetime so a later
    // securityd ACL park (see `withTimeout`) degrades to slightly-stale keys
    // instead of dead features.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    /// Run a keychain operation with a hard timeout. The legacy file keychain
    /// can park `SecItemCopyMatching` FOREVER when an item's ACL doesn't trust
    /// the current binary (the consent dialog never surfaces for a menu-bar
    /// app) — sampled live twice: it froze startup for 2 minutes and silently
    /// killed every model/TTS call after a re-sign. A blocked read now costs
    /// `seconds` and returns nil; callers already handle missing keys.
    /// (The abandoned thread stays parked — securityd releases it eventually;
    /// leaking a rare thread beats a dead assistant.)
    static func withTimeout<T>(_ seconds: TimeInterval, label: String,
                               _ work: @escaping () -> T?) -> T? {
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Thread.detachNewThread {
            box.value = work()
            sem.signal()
        }
        if sem.wait(timeout: .now() + seconds) == .timedOut {
            Log.trace("keychain: '\(label)' blocked >\(seconds)s — continuing without it")
            return nil
        }
        return box.value
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: T?
    }

    /// Save (or overwrite) a string value for `account`.
    ///
    /// Writes through `/usr/bin/security -A` (always-allow ACL): an item saved
    /// by SecItemAdd gets an ACL pinned to the saving binary's signature, so
    /// the next rebuild/re-sign makes every read of that item hang (the cycle
    /// that repeatedly broke dev builds live). Falls back to SecItemAdd when
    /// the CLI is unavailable.
    static func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }
        cacheLock.lock(); cache[account] = value; cacheLock.unlock()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["add-generic-password", "-U", "-A",
                          "-s", service, "-a", account, "-w", value]
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            if proc.terminationStatus == 0 { return }
        }
        // Fallback: classic API (ACL pinned to this binary — better than losing the key).
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Read the string value for `account`, or `nil` if absent. Never hangs:
    /// a blocked read times out and serves the in-process cache when possible.
    static func read(account: String) -> String? {
        let fresh: String? = withTimeout(5, label: account) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        }
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let fresh {
            cache[account] = fresh
            return fresh
        }
        return cache[account]
    }

    /// Remove the item for `account`. No-op if absent.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Well-known Keychain account keys.
enum KeychainKey {
    static let geminiAPIKey = "gemini_api_key"
    static let groqAPIKey = "groq_api_key"
    static let cerebrasAPIKey = "cerebras_api_key"
    static let openRouterAPIKey = "openrouter_api_key"
}
