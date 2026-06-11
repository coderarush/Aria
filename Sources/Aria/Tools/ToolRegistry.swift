import Foundation

/// Central registry of built-in static tools, keyed by `name`. The orchestrator
/// looks tools up here first; misses fall back to the DynamicToolFactory.
actor ToolRegistry {
    private var tools: [String: AriaTool] = [:]

    init(tools: [AriaTool] = ToolRegistry.builtins()) {
        for tool in tools { self.tools[type(of: tool).name] = tool }
    }

    func tool(named name: String) -> AriaTool? { tools[name] }
    func contains(_ name: String) -> Bool { tools[name] != nil }
    func allNames() -> [String] { tools.keys.sorted() }

    /// A short catalog the model can read to choose tools.
    func catalog() -> String {
        tools.values
            .map { "- \(type(of: $0).name): \(type(of: $0).description)" }
            .sorted()
            .joined(separator: "\n")
    }

    /// Tool specs (name/description/params) for enabled builtins, for building
    /// Gemini functionDeclarations.
    func specs() async -> [ToolSpec] {
        let disabled = await MainActor.run { AppSettings.shared.disabledTools }
        return tools.values
            .filter { !disabled.contains(type(of: $0).name) }
            .map { ToolSpec(name: type(of: $0).name,
                            description: type(of: $0).description,
                            params: type(of: $0).paramHints) }
    }

    /// The default built-in tool set.
    static func builtins() -> [AriaTool] {
        [
            ShellTool(),
            AppleScriptTool(),
            FileWriteTool(),
            FileReadTool(),
            FinderSelectionTool(),
            BrowserTabsTool(),
            ClipboardTool(),
            SaveNoteTool(),
            UndoTool(),
            EmailRecentTool(),
            EmailSearchTool(),
            EmailDraftTool(),
            SendMailTool(),
            CalendarTool(),
            RemindersTool(),
            NotificationTool(),
            OpenAppTool(),
            BrowserTool(),
            WebSearchTool(),
            WebFetchTool(),
            KnowledgeSearchTool(),
            RecallWorkTool(),
            TimelineTool(),
            NotesReadTool(),
            TabContentTool(),
            UIReadTool(),
            UIClickTool(),
            UITypeTool(),
            UIKeyTool(),
            UIScrollTool(),
            ScreenVisionTool()
        ]
    }
}
