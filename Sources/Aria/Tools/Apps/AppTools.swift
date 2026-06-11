import Foundation
import AppKit

/// Open an application by name.
struct OpenAppTool: AriaTool {
    static let name = "open_app"
    static let description = "Open an application by name. Input: {name}."
    static let paramHints: [String: String] = ["name": "The application name, e.g. Spotify"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let appName = input["name"], !appName.isEmpty else {
            throw ToolError.missingInput("name")
        }
        return await MainActor.run {
            let ws = NSWorkspace.shared
            if let url = ws.urlForApplication(withBundleIdentifier: appName)
                ?? Self.appURL(named: appName) {
                ws.open(url)
                return .ok("Opened \(appName).")
            }
            return .fail("Couldn't find app '\(appName)'.")
        }
    }

    @MainActor
    private static func appURL(named name: String) -> URL? {
        let candidates = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

/// Open a URL in the default browser.
struct BrowserTool: AriaTool {
    static let name = "open_url"
    static let description = "Open a URL in the default browser. Input: {url}."
    static let paramHints: [String: String] = ["url": "The URL to open, e.g. https://example.com"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let raw = input["url"], !raw.isEmpty else { throw ToolError.missingInput("url") }
        guard let url = Self.normalizedURL(raw) else { return .fail("Invalid URL: \(raw)") }
        return await MainActor.run {
            NSWorkspace.shared.open(url)
            return .ok("Opened \(url.absoluteString)")
        }
    }

    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: withScheme) { return url }
        let escaped = withScheme
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return URL(string: escaped)
    }
}
