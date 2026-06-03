import Foundation

/// Central registry of built-in static tools, keyed by `name`. The orchestrator
/// looks tools up here first; misses fall back to the DynamicToolFactory.
actor ToolRegistry {
    private var tools: [String: FridayTool] = [:]

    init(tools: [FridayTool] = ToolRegistry.builtins()) {
        for tool in tools { self.tools[type(of: tool).name] = tool }
    }

    func tool(named name: String) -> FridayTool? { tools[name] }
    func contains(_ name: String) -> Bool { tools[name] != nil }
    func allNames() -> [String] { tools.keys.sorted() }

    /// A short catalog the model can read to choose tools.
    func catalog() -> String {
        tools.values
            .map { "- \(type(of: $0).name): \(type(of: $0).description)" }
            .sorted()
            .joined(separator: "\n")
    }

    /// The default built-in tool set.
    static func builtins() -> [FridayTool] {
        [
            ShellTool(),
            AppleScriptTool(),
            FileWriteTool(),
            FileReadTool(),
            ClipboardTool(),
            NotificationTool(),
            OpenAppTool(),
            BrowserTool(),
            WebSearchTool(),
            WebFetchTool()
        ]
    }
}
