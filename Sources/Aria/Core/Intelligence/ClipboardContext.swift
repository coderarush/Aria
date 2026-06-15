import Foundation
import AppKit

/// Polls the system clipboard and maintains a short history of unique values.
/// Injected into PersonalContextEngine so the model has ambient awareness of
/// what the user copied without fetching live pasteboard data on every turn.
actor ClipboardContext {
    static let shared = ClipboardContext()

    /// Injectable for tests — replaces NSPasteboard.general.string(forType:.string).
    var readClipboard: @Sendable () -> String?

    /// Poll interval in seconds. Default 2.0; tests inject a faster value.
    var pollInterval: Double

    private(set) var current: String?
    private(set) var history: [String] = []

    private var pollingTask: Task<Void, Never>?
    private let historyLimit = 5

    init() {
        readClipboard = {
            NSPasteboard.general.string(forType: .string)
        }
        pollInterval = 2.0
    }

    /// Set the clipboard reader (for testing from async contexts).
    func setReadClipboard(_ reader: @escaping @Sendable () -> String?) {
        readClipboard = reader
    }

    /// Set the poll interval (for testing from async contexts).
    func setPollInterval(_ interval: Double) {
        pollInterval = interval
    }

    /// Start the clipboard polling loop.
    func start() async {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                guard let interval = await self?.pollInterval else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stop the clipboard polling loop.
    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Returns the current clipboard content (trimmed), or nil if empty.
    func snapshot() async -> String? {
        guard let value = current?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: Private

    private func poll() {
        guard let raw = readClipboard() else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current else { return }
        current = trimmed
        history.insert(trimmed, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
    }
}
