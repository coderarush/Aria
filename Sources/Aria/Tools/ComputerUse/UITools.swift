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
        let ok = await MainActor.run(body: { UIActuator.click(role: role, label: label) })
        if ok { return .ok("Clicked “\(label)”.") }
        // Accessibility couldn't find it (Electron/canvas/custom UI) → locate by sight.
        if let pt = await VisionLocator.locate(label) {
            await MainActor.run { UIActuator.clickAt(pt) }
            return .ok("Clicked “\(label)” (located by sight).")
        }
        return .fail("Couldn't find “\(label)” on screen, even by sight. Call ui_read to see the exact labels.")
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
