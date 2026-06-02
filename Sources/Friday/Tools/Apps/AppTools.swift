import Foundation
import AppKit

/// Open an application by name.
struct OpenAppTool: FridayTool {
    static let name = "open_app"
    static let description = "Open an application by name. Input: {name}."

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
struct BrowserTool: FridayTool {
    static let name = "open_url"
    static let description = "Open a URL in the default browser. Input: {url}."

    func run(input: [String: String]) async throws -> ToolResult {
        guard let raw = input["url"], !raw.isEmpty else { throw ToolError.missingInput("url") }
        let normalized = raw.hasPrefix("http") ? raw : "https://\(raw)"
        guard let url = URL(string: normalized) else { return .fail("Invalid URL: \(raw)") }
        return await MainActor.run {
            NSWorkspace.shared.open(url)
            return .ok("Opened \(normalized)")
        }
    }
}
