import Foundation

/// Aria's core differentiator: when no existing tool fits, ask Gemini to write
/// a fresh script, run it safely, and optionally persist it as a reusable tool.
actor DynamicToolFactory {

    private let gemini: GeminiClient
    private let runner: ScriptRunner
    private let toolsDir: URL

    init(gemini: GeminiClient = GeminiClient(),
         runner: ScriptRunner = ScriptRunner(),
         toolsDir: URL? = nil) {
        self.gemini = gemini
        self.runner = runner
        self.toolsDir = toolsDir ?? Self.defaultToolsDir()
        try? FileManager.default.createDirectory(at: self.toolsDir, withIntermediateDirectories: true)
    }

    static func defaultToolsDir() -> URL {
        PersistencePaths.applicationSupportBaseDirectory()
            .appendingPathComponent("tools", isDirectory: true)
    }

    // MARK: Generation

    /// Ask Gemini to write a tool for `task`. The returned tool is unsaved.
    func generateTool(for task: String,
                      language: ToolLanguage = .python,
                      context: GeminiClient.SystemContext) async throws -> GeneratedTool {
        let code = try await gemini.generateScript(task: task, language: language, context: context)
        guard !code.isEmpty else { throw ToolError.executionFailed("model returned no code") }
        return GeneratedTool(
            name: Self.slug(from: task),
            description: task,
            language: language,
            code: code,
            source: .generated)
    }

    // MARK: Execution

    /// Execute a generated tool with the configured timeout.
    func execute(_ tool: GeneratedTool, timeout: TimeInterval = 60) async -> ToolResult {
        do {
            let out = try await runner.run(code: tool.code, language: tool.language, timeout: timeout)
            if out.success {
                return .ok(out.stdout.isEmpty ? "(no output)" : out.stdout,
                           diagnostics: out.stderr.isEmpty ? nil : out.stderr)
            }
            return .fail("Script exited \(out.exitCode).",
                         diagnostics: out.stderr.isEmpty ? out.stdout : out.stderr)
        } catch ToolError.timedOut {
            return .fail("Timed out after the limit.")
        } catch ToolError.interpreterNotFound(let lang) {
            return .fail("No interpreter found for \(lang).")
        } catch {
            return .fail("Execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: Persistence

    @discardableResult
    func saveTool(_ tool: GeneratedTool, name: String? = nil, description: String? = nil) -> GeneratedTool {
        var saved = tool
        if let name { saved.name = Self.slug(from: name) }
        if let description { saved.description = description }
        write(saved)
        return saved
    }

    func loadPersistedTools() -> [GeneratedTool] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: toolsDir, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(GeneratedTool.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func recordUsage(_ id: UUID) {
        var tools = loadPersistedTools()
        guard let idx = tools.firstIndex(where: { $0.id == id }) else { return }
        tools[idx].usageCount += 1
        write(tools[idx])
    }

    @discardableResult
    func deleteTool(_ id: UUID) -> Bool {
        let url = toolsDir.appendingPathComponent("\(id.uuidString).json")
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    // MARK: Helpers

    private func write(_ tool: GeneratedTool) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = toolsDir.appendingPathComponent("\(tool.id.uuidString).json")
        if let data = try? encoder.encode(tool) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func slug(from task: String) -> String {
        let words = task.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
        let s = words.joined(separator: "_")
        return s.isEmpty ? "tool_\(UUID().uuidString.prefix(8))" : s
    }
}
