# Aria v11.0.1 — "Living Presence"

A UI + reliability point release that makes Aria feel alive and gives her a real home on the Mac.

## Highlights

- **Living presence.** Say her name and she becomes a soft, Siri-style glow rotating the screen edge. When you finish talking she **gathers from the edges and pools into the blob** with a water-like animation; on a task she **splashes to the edge** and works as the border, then **consolidates back into the blob and explains what she did.** Liquid-glass smooth, dim and ambient — nothing on screen when idle.
- **Drag her anywhere.** Move the blob to any corner; the spot is saved and she reappears there.
- **System-wide dictation (⌥⇧D).** Hold the hotkey, talk into any app's text field, and the cleaned-up text is typed at your cursor — distinct from talking *to* her.
- **Premium app window.** A real app beyond the orb (⌘O): Home dashboard, searchable conversations, activity, an Insights view of what she's learned, and a connectors page.
- **Connectors (OAuth).** PKCE OAuth framework + Keychain token store + Gmail/Calendar read tools.
- **Faster.** Cerebras/Groq fast-cloud path fronts Gemini for snappier first-token; dedicated fast local instruct model for on-device voice; local-first voice on by default (falls back to cloud).
- **Mac-wide context + proactive precision.** Recent files / apps / messages / calendar awareness; confidence-gated, daily-budgeted proactive nudges.

## Engineering

- 490+ tests, release build pinned to `-Onone` (macOS 26.3.x optimizer crash mitigation), verified.

Requirements: macOS 14+.
