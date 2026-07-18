import Foundation

/// Orion — searches the web, fetches the top sources, and synthesizes a short report.
struct ResearchAgent: SubAgent {
    let name = "Orion"
    let description = "Research a topic: search the web, read sources, synthesize a report."
    let persona = "tracks down anything on the web"
    let allowedTools = ["web_search", "web_fetch"]

    func execute(task: String, context: AgentContext) async -> AgentResult {
        let search = await context.runAction(
            AgentAction(tool: "web_search", input: ["query": task]), "")
        guard search.success else { return .fail("Search failed: \(search.output)") }

        // Pull any URLs out of the search output to read deeper.
        let urls = ResearchAgent.extractURLs(from: search.output).prefix(2)
        var sources = search.output
        for url in urls {
            let fetched = await context.runAction(
                AgentAction(tool: "web_fetch", input: ["url": url]), "")
            if fetched.success { sources += "\n\n--- \(url) ---\n" + fetched.output }
        }

        // Synthesize with the model.
        let synthTask = """
        Write a concise report on "\(task)" using these sources. Use markdown with \
        a short summary and 3-5 bullet key points.

        SOURCES:
        \(String(sources.prefix(8000)))
        """
        let report = (try? await context.gemini.generateText(prompt: synthTask, temperature: 0.3)) ?? ""
        return .ok(report.isEmpty ? String(sources.prefix(2000)) : report)
    }

    static func extractURLs(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url?.absoluteString }
    }
}

/// Nova — writes code from a description, saves it to a file, and optionally runs it.
struct CodeWriterAgent: SubAgent {
    let name = "Nova"
    let description = "Write code from a description, save to a file, optionally run it."
    let persona = "writes and runs code on the fly"
    let allowedTools = ["file_write"]

    func execute(task: String, context: AgentContext) async -> AgentResult {
        let language = ToolLanguage(rawValue: AgentContext.languageHint(in: task)) ?? .python
        let tool: GeneratedTool
        do {
            tool = try await context.factory.generateTool(
                for: task, language: language, context: context.system)
        } catch {
            return .fail("Couldn't generate code: \(error.localizedDescription)")
        }

        // Save to Desktop with a slugged filename.
        let ext = language == .python ? "py" : language == .javascript ? "js" : "sh"
        let path = "\(NSHomeDirectory())/Desktop/\(tool.name).\(ext)"
        let write = await context.runAction(
            AgentAction(tool: "file_write", input: ["path": path, "content": tool.code]), "")

        var output = write.success ? "Saved \(tool.name).\(ext) to Desktop." : "Couldn't save file."
        if task.lowercased().contains("run") {
            let result = await context.factory.execute(tool, timeout: 60)
            output += "\n\nOutput:\n" + result.output
        }
        return .ok(output, artifacts: write.success ? [path] : [])
    }
}

/// Atlas — breaks a goal into ordered tool actions and runs them sequentially.
struct TaskPlannerAgent: SubAgent {
    let name = "Atlas"
    let description = "Break a complex goal into steps and execute them in order."
    let persona = "operates the Mac — apps, files, system"
    let allowedTools = ["shell", "applescript", "open_app", "file_write", "file_read", "clipboard", "save_note", "open_url"]

    func execute(task: String, context: AgentContext) async -> AgentResult {
        let catalog = await context.registry.catalog()
        let planPrompt = """
        You operate this Mac and can accomplish anything via these tools (shell + \
        applescript reach any app/file/setting). Break this goal into an ordered list \
        of tool steps. Output ONLY a JSON array like [{"tool":"name","input":{...}}]. \
        To save/record text for the user use tool "save_note". Use tool "dynamic" with \
        input.task for anything no listed tool covers. Never refuse.

        GOAL: \(task)

        TOOLS:
        \(catalog)
        """
        let raw = (try? await context.gemini.generateText(prompt: planPrompt, temperature: 0.2)) ?? ""
        guard let actions = TaskPlannerAgent.parseActions(raw), !actions.isEmpty else {
            return .fail("Couldn't parse a plan.")
        }

        var transcript = ""
        var prior = ""
        for action in actions {
            let result = await context.runAction(action, prior)
            transcript += "\n• \(action.tool) → \(result.output.prefix(200))"
            prior = result.output
            if !result.success { break }
        }
        return .ok("Plan executed:\(transcript)")
    }

    static func parseActions(_ raw: String) -> [AgentAction]? {
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]"),
              let data = String(cleaned[start...end]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        // Coerce input values to strings (the model sometimes emits numbers/bools),
        // mirroring PlanParser — JSONDecoder([AgentAction]) would reject those.
        return arr.compactMap { obj in
            guard let tool = obj["tool"] as? String else { return nil }
            let input = (obj["input"] as? [String: Any])?.reduce(into: [String: String]()) {
                $0[$1.key] = String(describing: $1.value)
            } ?? [:]
            return AgentAction(tool: tool, input: input)
        }
    }
}

/// Lyra — writes/drafts prose (emails, notes, summaries) and saves/copies it.
struct LyraAgent: SubAgent {
    let name = "Lyra"
    let description = "Write or draft text — emails, notes, docs, summaries — and save or copy it."
    let persona = "the wordsmith — drafts and writes"
    let allowedTools = ["file_write", "clipboard"]

    func execute(task: String, context: AgentContext) async -> AgentResult {
        let prompt = "Write the following as clean, well-formatted prose. Output ONLY the prose, no preamble:\n\(task)"
        let text = (try? await context.gemini.generateText(prompt: prompt, temperature: 0.4)) ?? ""
        let clean = text.isEmpty ? task : text
        _ = await context.runAction(AgentAction(tool: "clipboard", input: ["action": "write", "text": clean]), "")
        return .ok(clean)
    }
}

/// Comet — messages & mail. Drafting is free; SENDING is gated upstream (Safety).
struct CometAgent: SubAgent {
    let name = "Comet"
    let description = "Compose and (with confirmation) send messages or mail via the Mail/Messages apps."
    let persona = "the courier — handles mail and messages"
    let allowedTools = ["applescript", "clipboard"]

    func execute(task: String, context: AgentContext) async -> AgentResult {
        // The task is natural language ("email John the summary"), not AppleScript —
        // generate the script first, then run it. Sending is gated by the Safety
        // confirm in the orchestrator's execute().
        let prompt = """
        Write AppleScript to accomplish this on macOS using the Mail or Messages app. \
        Output ONLY the AppleScript source, no explanation, no code fences.

        TASK: \(task)
        """
        let script = (try? await context.gemini.generateText(prompt: prompt, temperature: 0.2)) ?? ""
        let clean = GeminiClient.stripCodeFences(script)
        guard !clean.isEmpty else { return .fail("Couldn't compose that message.") }
        let result = await context.runAction(AgentAction(tool: "applescript", input: ["script": clean]), "")
        return result.success ? .ok(result.output) : .fail(result.output)
    }
}

/// Pilot — operates any Mac app's UI (sees the screen, clicks, types). Runs a capped
/// perceive→act→perceive loop, because GUIs need to be re-read after each action.
struct PilotAgent: SubAgent {
    let name = "Pilot"
    let description = "Operate any app's interface — click buttons, fill fields, run menus — to accomplish a goal on screen."
    let persona = "the operator — drives apps hands-on"
    let allowedTools = ["ui_read", "ui_click", "ui_type", "ui_key", "ui_scroll", "open_app"]

    func execute(task: String, context: AgentContext) async -> AgentResult {
        var log = ""
        for _ in 0..<10 {
            let screen = await context.runAction(AgentAction(tool: "ui_read", input: [:]), "")
            let prompt = """
            You operate this Mac's UI to accomplish: \(task)

            What's on screen now:
            \(screen.output)

            Actions so far:\(log.isEmpty ? " (none)" : log)

            Reply with ONE next action as a single JSON object and nothing else:
            {"tool":"ui_click","input":{"label":"…"}}  OR  {"tool":"ui_type","input":{"text":"…"}}
            {"tool":"ui_key","input":{"combo":"cmd+s"}}  OR  {"tool":"ui_scroll","input":{"direction":"down"}}
            {"tool":"done","input":{"summary":"…"}}
            Use "done" when the goal is complete or impossible.
            """
            let raw = (try? await context.gemini.generateText(prompt: prompt, temperature: 0.1)) ?? ""
            guard let action = PilotAgent.parse(raw) else { break }
            if action.tool == "done" { return .ok(action.input["summary"] ?? "Done.\(log)") }
            let r = await context.runAction(AgentAction(tool: action.tool, input: action.input), "")
            log += "\n• \(action.tool)(\(action.input.values.joined(separator: ","))) → \(r.output.prefix(60))"
            if !r.success { log += " [failed]" }
        }
        return .ok("Operated the app.\(log)")
    }

    static func parse(_ raw: String) -> (tool: String, input: [String: String])? {
        let cleaned = GeminiClient.stripCodeFences(raw)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"),
              let data = String(cleaned[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = obj["tool"] as? String else { return nil }
        let input = (obj["input"] as? [String: Any])?.reduce(into: [String: String]()) {
            $0[$1.key] = String(describing: $1.value)
        } ?? [:]
        return (tool, input)
    }
}

extension AgentContext {
    /// Cheap language sniff from a task string for CodeWriterAgent.
    static func languageHint(in task: String) -> String {
        let t = task.lowercased()
        if t.contains("javascript") || t.contains("node") { return "javascript" }
        if t.contains("bash") || t.contains("shell") { return "bash" }
        if t.contains("applescript") { return "applescript" }
        return "python"
    }
}
