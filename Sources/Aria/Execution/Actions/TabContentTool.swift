import Foundation

/// Read the CONTENT of the active browser tab — completes the browser
/// integration (browser_tabs lists tabs; this fetches what the user is
/// actually reading). Gets the front tab's URL via AppleScript
/// (Safari/Chrome/Arc/Brave/Edge), then fetches the page like web_fetch.
struct TabContentTool: AriaTool {
    static let name = "tab_content"
    static let description = "Read the content of the browser tab the user is currently viewing. No input. Use for 'summarize this article', 'what does this page say', 'the tab I'm reading'."

    func run(input: [String: String]) async throws -> ToolResult {
        guard let url = await Self.frontTabURL() else {
            return .fail("I couldn't see an active browser tab — is a browser frontmost? (Automation access may be needed.)")
        }
        // Reuse the proven page-fetch path.
        return try await WebFetchTool().run(input: ["url": url])
    }

    /// The frontmost supported browser's active-tab URL.
    static func frontTabURL() async -> String? {
        let candidates: [(String, String)] = [
            ("Safari", "tell application \"Safari\" to if (count of windows) > 0 then return URL of current tab of front window"),
            ("Google Chrome", "tell application \"Google Chrome\" to if (count of windows) > 0 then return URL of active tab of front window"),
            ("Arc", "tell application \"Arc\" to if (count of windows) > 0 then return URL of active tab of front window"),
            ("Brave Browser", "tell application \"Brave Browser\" to if (count of windows) > 0 then return URL of active tab of front window"),
            ("Microsoft Edge", "tell application \"Microsoft Edge\" to if (count of windows) > 0 then return URL of active tab of front window"),
        ]
        for (app, script) in candidates {
            let running = await AppleScriptTool.execute(
                "tell application \"System Events\" to (name of processes) contains \"\(app)\"")
            guard running.success, running.output.contains("true") else { continue }
            let result = await AppleScriptTool.execute(script)
            let url = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.success, url.hasPrefix("http") { return url }
        }
        return nil
    }
}
