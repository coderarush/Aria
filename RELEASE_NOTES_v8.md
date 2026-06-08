# Aria v8

**The Mac assistant that actually does it — now more reliable, faster, and able to finish long jobs on its own.**

Aria is a free, native macOS voice agent. Say **“Hey Aria”** and she hears you, sees your screen, and operates your apps by voice — she does the task, she doesn't just explain it. v8 is a large release focused on reliability, speed, awareness, and long-running work.

---

## Highlights

- **Email, by voice.** Read your inbox, search it, draft a reply, and send — through Apple Mail, so it works with your Gmail (or any) account, no setup. Sending always asks first.
- **Finishes long jobs by herself.** Give her a multi-step objective and walk away — she notifies you when it's done, and if the app quits or crashes mid-task she offers to **resume right where she left off**.
- **Undo + a visible activity log.** Every action is recorded (Settings → Activity). Roll back her last change with “undo that.”
- **Faster and calmer.** Lower-latency planning, parallel turn setup, and bounded timeouts so a stalled request can't freeze a task.
- **Knows more, asks less.** Pulls your clipboard, Finder selection, and the browser tab you're reading — only when the task needs it — and brings what she remembers about you into her planning.

---

## What's new in v8

### Reliability
- Declining a confirmation no longer re-prompts you for the same action.
- Network/API outages are explained honestly (“check your connection / key”) instead of a vague “I couldn't work that out.”
- One unified safety gate now covers **every** path — destructive tools, financial/system actions, and generated code alike.
- **Durable activity log:** every action Aria takes is recorded and visible in **Settings → Activity**, and survives restarts.
- **Undo system:** roll back her last reversible change (a file write, a clipboard change). Say “undo that.”
- Exactly one confirmation per action (the old double-prompt is gone); smarter retries that back off and don't waste a turn on a failure that won't change.

### Speed
- Planning and self-recovery use a faster model; turn setup (screen, history, context, tools, memory) now runs in parallel — lower time-to-first-response.
- Requests are time-bounded, so a stalled call fails fast to a fallback instead of hanging.
- **On-demand screen vision:** ordinary turns skip the redundant screenshot; Aria looks only when she actually needs to *see*.

### Awareness (context)
- New, intentional context sources, pulled only when the command calls for them: **clipboard**, **Finder selection**, and **open browser tabs**.

### Cross-app workflows + email
- **Email via Apple Mail** (Gmail-capable): `email_recent`, `email_search`, `email_draft`, and a confirmation-gated `send_mail`.
- Multi-step workflows thread **every** prior result forward, so “research A, research B, write a report” actually combines both.

### Memory
- What Aria remembers about you now feeds her **planning**, so she applies known preferences instead of asking twice.

### Long-running agents
- **Completion notifications** for multi-step tasks — you don't have to watch the orb.
- **Resumable tasks:** an interrupted objective is journaled to disk; relaunch and Aria offers to continue. Say “resume.”

### Identity
- The single morphing **“alive” orb** — calm when idle, swelling with your voice, swirling while she thinks, breathing while she speaks — remains Aria's face.

---

## Fixes
- Correct AppleScript escaping for multi-line email bodies.
- Added the **Automation** usage description (required for the Mail/Finder/browser tools).
- Robust task-journal persistence (creates its own storage directory).
- Version metadata corrected to 8.0.0.

---

## Install

> **Pre-release · Apple Silicon · not notarized.** macOS 14+. On first launch, **right-click the app → Open** to get past Gatekeeper.

1. Download **`Aria.dmg`** from the release assets, drag Aria to Applications, and launch (right-click → Open the first time).
2. Grant **Microphone + Speech Recognition** (wake word) and **Accessibility** (to operate apps). The **Automation** prompt appears the first time she touches Mail / Finder / your browser.
3. Add a free [Gemini API key](https://aistudio.google.com/app/apikey) in **Settings → API Key**.
4. Say **“Hey Aria.”**

---

## Notes
- Free on your own key — Gemini free tier, with automatic fallback across Groq / Cerebras / OpenRouter, and Ollama offline. No subscription, no servers.
- 195 unit tests, all green. Release built with whole-module optimization disabled (required on Swift 6.3 / macOS 26).
- Build from source: `make test && make release` (or `make dmg`). Universal/Intel + notarized distribution needs a paid Apple Developer ID (`make notarize`).

**Full changelog:** https://github.com/coderarush/Aria/compare/v7.0.0...v8.0.0
