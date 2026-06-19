import Foundation

/// See the frontmost app's controls so the model knows what it can click/type.
struct UIReadTool: AriaTool {
    static let name = "ui_read"
    static let description = "See the on-screen controls of the frontmost app (buttons, fields, menus, links). Call this BEFORE ui_click/ui_type so you know the exact labels. Input: {}."
    static let paramHints: [String: String] = [:]

    func run(input: [String: String]) async throws -> ToolResult {
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            await MainActor.run { AXReader.requestPermission() }
            return .fail("I need Accessibility access first — enable Aria in System Settings → Privacy & Security → Accessibility (I just opened the prompt), then try again.")
        }
        let els = await MainActor.run(body: { AXReader.readFrontmost() })
        let app = await MainActor.run(body: { AXReader.frontmostAppName() })
        return .ok("Controls in \(app):\n\(AXReader.summarize(els))")
    }
}

/// Click a control by its label.
struct UIClickTool: AriaTool {
    static let name = "ui_click"
    static let description = "Click a control in the frontmost app by its visible label. Input: {label, role?}. Use ui_read first to get exact labels."
    static let paramHints: [String: String] = [
        "label": "The control's visible text (e.g. Export, Save, Send)",
        "role": "Optional element role to disambiguate (e.g. AXButton)"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let label = input["label"], !label.isEmpty else { throw ToolError.missingInput("label") }
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            return .fail("Accessibility access is off — enable Aria in System Settings → Privacy & Security → Accessibility.")
        }
        await MainActor.run { NotificationCenter.default.post(name: .ariaUIActivity, object: nil) }
        let role = (input["role"]?.isEmpty == false) ? input["role"] : nil
        // Confidence-gated path: re-resolves the target (AX first, vision fallback) and only
        // clicks when we're sure enough. Below threshold we ask rather than click a guess.
        switch await UIActuator.clickConfident(role: role, label: label) {
        case .clicked:
            return .ok("Clicked “\(label)”.")
        case .unsure(let l):
            return .fail("I found something that might be “\(l)”, but I'm not confident it's the right control. Can you confirm the exact label, or click it yourself? (Call ui_read to see the labels I can see.)")
        case .notFound:
            return .fail("Couldn't find “\(label)” on screen, even by sight. Call ui_read to see the exact labels.")
        }
    }
}

/// Type text into the focused field.
struct UITypeTool: AriaTool {
    static let name = "ui_type"
    static let description = "Type text into the currently focused field of the frontmost app. Click the field first if needed. Input: {text}."
    static let paramHints: [String: String] = ["text": "The text to type"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let text = input["text"], !text.isEmpty else { throw ToolError.missingInput("text") }
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            return .fail("Accessibility access is off — enable Aria in System Settings → Privacy & Security → Accessibility.")
        }
        // Verify a text field is actually focused first — otherwise the keystrokes vanish
        // and we'd falsely report success. An honest failure lets the model click the field
        // and self-heal (the autonomy engine retries the step).
        let pid = await MainActor.run { AXReader.frontmostTarget()?.processIdentifier }
        let focusedRole = pid.map { ScreenContext.snapshot(pid: $0).focusedRole } ?? ""
        guard AXReader.canTypeInto(focusedRole: focusedRole) else {
            return .fail("No text field is focused — click the field you want to type into first, then I'll type.")
        }
        await MainActor.run { NotificationCenter.default.post(name: .ariaUIActivity, object: nil); UIActuator.type(text) }
        return .ok("Typed \(text.count) characters.")
    }
}

/// Scroll the frontmost app.
struct UIScrollTool: AriaTool {
    static let name = "ui_scroll"
    static let description = "Scroll the frontmost app. Input: {direction: up|down|left|right, amount? (pixels, default 400)}."
    static let paramHints: [String: String] = ["direction": "up, down, left, or right", "amount": "pixels to scroll"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            return .fail("Accessibility access is off — enable Aria in System Settings → Privacy & Security → Accessibility.")
        }
        let amt = Int(input["amount"] ?? "400") ?? 400
        let (dx, dy): (Int, Int)
        switch (input["direction"] ?? "down").lowercased() {
        case "up": (dx, dy) = (0, -amt)
        case "left": (dx, dy) = (-amt, 0)
        case "right": (dx, dy) = (amt, 0)
        default: (dx, dy) = (0, amt)   // down
        }
        await MainActor.run { NotificationCenter.default.post(name: .ariaUIActivity, object: nil); UIActuator.scroll(dx: dx, dy: dy) }
        return .ok("Scrolled \(input["direction"] ?? "down").")
    }
}

/// Right-click a control to open its context menu.
struct UIRightClickTool: AriaTool {
    static let name = "ui_right_click"
    static let description = "Right-click (secondary click) a control in the frontmost app by its visible label to open its context menu. Input: {label, role?}. Follow with ui_click to pick an item from the menu that appears."
    static let paramHints: [String: String] = [
        "label": "The control's visible text to right-click (e.g. a file name, a selection)",
        "role": "Optional element role to disambiguate (e.g. AXRow)"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let label = input["label"], !label.isEmpty else { throw ToolError.missingInput("label") }
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            return .fail("Accessibility access is off — enable Aria in System Settings → Privacy & Security → Accessibility.")
        }
        let role = (input["role"]?.isEmpty == false) ? input["role"] : nil
        let ok = await MainActor.run(body: {
            NotificationCenter.default.post(name: .ariaUIActivity, object: nil)
            return UIActuator.rightClick(role: role, label: label)
        })
        return ok ? .ok("Opened the context menu on “\(label)”. Call ui_read to see the menu items, then ui_click one.")
                  : .fail("Couldn't find “\(label)” to right-click. Call ui_read to see the exact labels.")
    }
}

/// Invoke a menu-bar command by path — the fast path for the ~30% of Mac
/// workflows that live in menus rather than on-screen buttons.
struct UIMenuTool: AriaTool {
    static let name = "ui_menu"
    static let description = "Invoke a menu-bar command in the frontmost app by path, e.g. \"Format > Font > Bold\" or \"File > Export…\". Walks the real menu bar and clicks the item — no need to ui_read first. Input: {path}."
    static let paramHints: [String: String] = ["path": "Menu path separated by > , e.g. File > New Window"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let path = input["path"], !path.isEmpty else { throw ToolError.missingInput("path") }
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            return .fail("Accessibility access is off — enable Aria in System Settings → Privacy & Security → Accessibility.")
        }
        let components = UIActuator.menuPath(path)
        guard !components.isEmpty else { return .fail("That doesn't look like a menu path. Try something like “File > Export”.") }
        let ok = await MainActor.run(body: {
            NotificationCenter.default.post(name: .ariaUIActivity, object: nil)
            return UIActuator.clickMenuPath(components)
        })
        return ok ? .ok("Chose \(components.joined(separator: " → ")).")
                  : .fail("Couldn't find the menu item “\(components.joined(separator: " → "))” in \(await MainActor.run(body: { AXReader.frontmostAppName() })). Check the exact menu names.")
    }
}

/// Press a keyboard shortcut.
struct UIKeyTool: AriaTool {
    static let name = "ui_key"
    static let description = "Press a keyboard shortcut in the frontmost app. Input: {combo} e.g. \"cmd+s\", \"enter\", \"cmd+shift+z\"."
    static let paramHints: [String: String] = ["combo": "Key combo, e.g. cmd+s, enter, cmd+c"]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let combo = input["combo"], !combo.isEmpty else { throw ToolError.missingInput("combo") }
        guard await MainActor.run(body: { AXReader.hasPermission }) else {
            return .fail("Accessibility access is off — enable Aria in System Settings → Privacy & Security → Accessibility.")
        }
        let ok = await MainActor.run(body: { NotificationCenter.default.post(name: .ariaUIActivity, object: nil); return UIActuator.key(combo) })
        return ok ? .ok("Pressed \(combo).") : .fail("Didn't recognize the key combo “\(combo)”.")
    }
}

/// Look at the screen and answer a question about it — for visual content the
/// accessibility text can't convey (diagrams, images, video frames, custom-drawn
/// UIs). The on-demand counterpart to ambient AX context: the model calls this
/// when it actually needs to *see*, so ordinary turns don't pay for a screenshot.
/// Capture stays in memory (never written to disk); secure fields are hidden by macOS.
struct ScreenVisionTool: AriaTool {
    static let name = "look_at_screen"
    static let description = "Look at what's currently on the screen and answer a question about it — diagrams, images, video frames, or anything visual the on-screen text can't describe. Use when you need to SEE the screen, not just read its controls. Input: {question?}."
    static let paramHints: [String: String] = ["question": "What to look for or answer about the screen"]

    var gemini: GeminiClient = GeminiClient()
    var screen: ScreenCaptureEngine = ScreenCaptureEngine()

    func run(input: [String: String]) async throws -> ToolResult {
        guard let jpeg = try? await screen.capturePrimaryJPEG() else {
            return .fail("I couldn't capture the screen — Screen Recording permission may be off (System Settings → Privacy & Security → Screen Recording).")
        }
        let question = (input["question"] ?? input["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = question.isEmpty ? "Describe what's on the screen." : question
        let prompt = "Look at this screenshot and answer concisely: \(ask)"
        let answer = ((try? await gemini.generateTextWithImage(prompt: prompt, jpeg: jpeg)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty
            ? .fail("I captured the screen but couldn't make out an answer just now.")
            : .ok(answer)
    }
}
