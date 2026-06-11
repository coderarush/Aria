<div align="center">

# Aria

**The Mac assistant that actually does it.**

Aria is a free, native macOS voice agent. Say **“Hey Aria”** and she hears you, sees your
screen, and operates your apps by voice — she does the task, she doesn't just explain it.

[Download](https://github.com/coderarush/Aria/releases/latest) ·
[Build from source](#build-from-source) ·
[How it works](#how-it-works)

**V10 pre-release (launch candidate)** — say **“brief me”** for your daily briefing, ask
*“what were we working on yesterday?”*, preview her plan before bigger tasks, and summon a
Raycast-grade palette with ⌥⇧Space — on top of V9's local-first intelligence, knowledge
engine, and background agents. Testers welcome.

</div>

---

Most “AI on your screen” tells you *how* to do something. Aria opens the app, finds the
button, types the message, and sends it — then tells you it's done. She lives in your menu
bar as a single morphing orb, wakes to her name entirely on-device, and runs **free** on
Google's Gemini free tier with your own key.

## What she does

- **Acts, doesn't narrate.** A real tool + sub-agent system: open apps, click and type in
  any app (Accessibility tree, with a vision fallback for canvas/Electron UIs), run menus,
  scroll, search and fetch the web, read and write files, calendar and reminders (EventKit),
  **email (Apple Mail — read, search, draft, send; works with Gmail accounts)**, clipboard,
  AppleScript, shell.
- **Ambient screen awareness.** Each turn she reads your focused window, the field you're in,
  and any selected text — so “summarize this”, “reply to her”, “translate the selection” just
  work, with no screenshot to attach. When she actually needs to *see* (a diagram, an image),
  she looks on demand; she can also pull your **clipboard**, **Finder selection**, and **open
  browser tabs** when the task calls for them — only when relevant, never by default.
- **Multi-step autonomy with play-by-play.** She plans, executes step by step, retries and
  self-heals, and says a short spoken play-by-play as she works (“Searching the web…”).
  Outputs flow forward across the whole workflow, so “research A, research B, write a report”
  actually combines both.
- **Long-running & resumable.** Kick off a multi-step objective and walk away — she notifies
  you when it's done, and if the app quits or crashes mid-task she offers to **resume right
  where she left off**.
- **Undo + a visible activity log.** Every action she takes is recorded (Settings → Activity),
  and you can **undo** her last reversible change (a file write, a clipboard change). Say
  “undo that.”
- **Remembers — and uses it.** Durable cross-session facts (“remember that…”) plus
  conversation memory, now fed into her planning so she applies what she knows about you
  instead of asking twice.
- **Free, on your key.** Bring a free [Gemini](https://aistudio.google.com) key (rotates
  across several), with automatic fallback to Groq / Cerebras / OpenRouter, and Ollama as an
  offline last resort. No subscription, no metered usage, no servers.
- **Private by design.** On-device wake word (`SFSpeechRecognizer`), keys in the macOS
  Keychain, screenshots never written to disk, secure fields never read.
- **Honest + safe.** She confirms before anything destructive (Send / Pay / Delete) and shows
  a visible “Aria is controlling your Mac” indicator with a Stop button while she drives.
- **Alive presence.** A single organic, morphing orb anchored to the corner: calm when idle,
  swelling with your voice, swirling while she thinks, breathing while she speaks. Soft
  synthesized chimes mark listening, task start, done, and errors — cancelled out of the mic
  by the echo canceller so she never hears herself.

### New in V9 (pre-release)

- **Local-first intelligence.** Planning, agents, knowledge and everyday work run on a local
  model (Ollama) by default — private, free, no quota — with automatic Gemini fallback the
  moment the local model can't deliver. Live conversation can go local too (Settings toggle;
  needs a fast instruct model such as `llama3.1:8b`). Vision and deep research stay on the
  cloud model.
- **Knowledge engine.** Point her at folders of notes, PDFs, documents and code
  (Settings → Knowledge). She indexes them on-device — incremental, never uploaded — and
  answers “what did the investor say about pricing?” from *your* files, with sources.
- **Background agents.** Set it once, let Aria handle it: a daily briefing at your hour, a
  Downloads-folder watcher, or any recurring goal (Settings → Agents). Runs are silent, use
  the same safety gates, always notify, and land in a visible history.
- **Push-to-talk & type.** `⌥Space` to talk without the wake word, `⌥⇧Space` for a floating
  type-to-Aria field — both coexist with “Hey Aria”. (Needs Accessibility, granted once.)
- **Proactive presence.** She anticipates: a calendar event coming up or a learned routine
  makes the orb glow softly. Glance or wake her and she leads with the offer; say “yes” or
  just ignore it. Suppresses anything you dismiss repeatedly.
- **Transparency.** Settings → Transparency shows what she sees right now, which model
  answered and why (the local/cloud router's reasons), and what ran in the background. No
  black boxes.
- **Make her yours.** Orb size and position, personality style (Balanced / Warm / Witty /
  Concise), interaction sounds, quiet hours — all in Settings.

## How it works

```
“Hey Aria”  ──►  on-device wake (SFSpeechRecognizer)
                      │
            speech ──►│  transcription + ambient screen context (AX)
                      ▼
              Gemini agent loop  ──►  tools / sub-agents / vision
                      │                    │
                 spoken reply  ◄───────────┘  (acts, verifies, narrates)
```

Wake and transcription run locally. Only your command (and, when needed, a screenshot) goes
to the model, using your own key. The agent loop calls tools, sees the results, and continues
until the task is done — then speaks the answer in a natural Gemini voice.

## Install

### Download

Grab the latest `.dmg` from [Releases](https://github.com/coderarush/Aria/releases/latest),
drag Aria to Applications, and launch. On first run, grant Microphone + Speech Recognition
(for the wake word) and, when prompted, Accessibility (so she can operate your apps). Add a
free Gemini key in Settings → API Key.

### Build from source

```bash
git clone https://github.com/coderarush/Aria.git
cd Aria
make test       # 335 unit tests
make release    # assemble Aria.app (ad-hoc signed)
open .build/Aria.app
```

Requirements: **macOS 14+**, **Xcode 16+** (Swift 6). For permissions that persist across
rebuilds, run `make cert` once (creates a stable self-signed identity). `make dmg` packages a
distributable disk image.

### Demo mode (press & testing)

Want to exercise the full product — orb, voice, tools UI — without any API key?

```bash
ARIA_DEMO_MODE=1 /Applications/Aria.app/Contents/MacOS/Aria
```

Model replies are scripted and deterministic (ask about *the meeting*, *downloads*,
*pricing*, or for *a joke*); everything else is the real engine. `ARIA_DEMO_SCRIPT=path.json`
swaps in your own script — this is also what powers the repeatable demo recordings and the
headless smoke suite (`make smoke`).

## Configuration

Aria uses your own [Google AI Studio](https://aistudio.google.com/app/apikey) key — the free
tier is enough. Add it in **Settings → API Key** (one key per line; she rotates across them as
each hits its daily free-tier limit). Optionally add free Groq / Cerebras / OpenRouter keys as
fallbacks, or enable a local Ollama model for offline use. Everything is stored in the macOS
Keychain and sent only to the provider you configured.

## Try saying

| Say | Aria does |
|---|---|
| “Summarize this.” | reads the focused window / selection, summarizes |
| “Check my email.” | reads your inbox (Apple Mail / Gmail) |
| “Draft a reply to Sarah saying I'm running late.” | prepares a draft for you to review |
| “Open my notes and start a list.” | drives apps across steps, by herself |
| “What's on my calendar Thursday?” | EventKit, on-device |
| “Rename the selected files in Finder.” | acts on your Finder selection |
| “Summarize the article I'm reading.” | reads the active browser tab |
| “Format what I just copied.” | pulls your clipboard, on demand |
| “Undo that.” | rolls back her last reversible change |
| “Resume.” | picks up an interrupted task where it left off |
| “Find the export button and click it.” | sees the screen and clicks it |

## Architecture

```
Sources/Aria/
├── App/        AriaApp, AppDelegate (menu bar), AriaController (wiring)
├── Core/       WakeWordEngine, AudioBus (+ AEC), GeminiClient, AgentOrchestrator,
│              ActivityLog (durable, traceable), UndoStack (rollback)
│   ├── ComputerUse/   AXReader, UIActuator, ScreenContext, VisionLocator, ContextRelevance
│   ├── Autonomy/      AutonomyEngine, Safety, TaskNarration, TaskStore (resumable tasks)
│   ├── Memory/        LongTermMemory, MemoryCapture
│   ├── Licensing/     LicenseManager, UpdateChecker
│   └── Providers/     OpenAI-compatible fallback (Groq/Cerebras/OpenRouter/Ollama)
├── Tools/      AriaTool implementations (files, web, apps, EventKit, email/Mail,
│              Finder, browser, computer-use, vision, undo…)
├── UI/         IslandView + MorphingBlob, IslandViewModel, SettingsView, OnboardingView
└── Utilities/  KeychainManager, PermissionsManager, AppSettings, Logger

Sources/CSpeexDSP/   vendored Speex echo canceller (C) — the AEC far-end reference
                     that lets her talk and listen at once without hearing herself
```

Swift 6, SwiftUI + AppKit, structured concurrency (async/await + actors), MVVM. 195 unit
tests cover the model protocol, agent loop, tool declarations, autonomy, computer-use logic,
memory, the activity log, undo, resumable-task journaling, context relevance, voice chunking,
and the wake/barge state machines.

### Release builds ship the debug configuration — on purpose

On macOS 26.3.x the Swift optimizer miscompiles SwiftUI's actor isolation: optimized
release builds crash on the **first tap of any SwiftUI control** inside
`swift_task_isCurrentExecutorWithFlags` (v8 hit it via whole-module optimization,
EXC_BAD_ACCESS; on 26.3.1 it reproduces even with WMO off and `-Onone`). The debug
configuration has never crashed, so `make release` bundles the debug binary until the
toolchain bug is fixed — `make verify-release` guards the choice. The cost is negligible:
the app is network/disk-bound and the only hot real-time path (echo cancellation) is C.
If a first-tap crash ever returns, check the build flags before suspecting code.

## Privacy

Aria has no backend. Wake-word detection is on-device; your keys live in the Keychain;
screenshots are captured only on command and never written to disk; secure text fields are
hidden from her screen-context read by macOS. The only network calls are to the AI provider
you configured, with your own key.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — especially how to add a new tool.

## License

MIT.
