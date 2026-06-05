<div align="center">

# Aria

**The Mac assistant that actually does it.**

Aria is a free, native macOS voice agent. Say **“Hey Aria”** and she hears you, sees your
screen, and operates your apps by voice — she does the task, she doesn't just explain it.

[Download](https://github.com/coderarush/Aria/releases/latest) ·
[Build from source](#build-from-source) ·
[How it works](#how-it-works)

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
  clipboard, AppleScript, shell.
- **Ambient screen awareness.** Each turn she reads your focused window, the field you're in,
  and any selected text — so “summarize this”, “reply to her”, “translate the selection” just
  work, with no screenshot to attach. Deep content escalates to on-command screen vision.
- **Multi-step autonomy with play-by-play.** She plans, executes step by step, retries and
  self-heals, and says a short spoken play-by-play as she works (“Searching the web…”).
- **Remembers.** Durable cross-session facts (“remember that…”) plus conversation memory.
- **Free, on your key.** Bring a free [Gemini](https://aistudio.google.com) key (rotates
  across several), with automatic fallback to Groq / Cerebras / OpenRouter, and Ollama as an
  offline last resort. No subscription, no metered usage, no servers.
- **Private by design.** On-device wake word (`SFSpeechRecognizer`), keys in the macOS
  Keychain, screenshots never written to disk, secure fields never read.
- **Honest + safe.** She confirms before anything destructive (Send / Pay / Delete) and shows
  a visible “Aria is controlling your Mac” indicator with a Stop button while she drives.
- **Alive presence.** A single organic, morphing orb anchored to the corner: calm when idle,
  swelling with your voice, swirling while she thinks, breathing while she speaks.

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
make test       # 166 unit tests
make release    # assemble Aria.app (ad-hoc signed)
open .build/Aria.app
```

Requirements: **macOS 14+**, **Xcode 16+** (Swift 6). For permissions that persist across
rebuilds, run `make cert` once (creates a stable self-signed identity). `make dmg` packages a
distributable disk image.

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
| “Reply to her — I'm running late.” | composes in the open mail thread |
| “Open my notes and start a list.” | drives apps across steps, by herself |
| “What's on my calendar Thursday?” | EventKit, on-device |
| “Translate the selection to French.” | acts on whatever's highlighted |
| “Find the export button and click it.” | sees the screen and clicks it |

## Architecture

```
Sources/Aria/
├── App/        AriaApp, AppDelegate (menu bar), AriaController (wiring)
├── Core/       WakeWordEngine, AudioBus (+ AEC), GeminiClient, AgentOrchestrator,
│   ├── ComputerUse/   AXReader, UIActuator, ScreenContext, VisionLocator
│   ├── Autonomy/      AutonomyEngine, Safety, TaskNarration
│   ├── Licensing/     LicenseManager, UpdateChecker
│   └── Providers/     OpenAI-compatible fallback (Groq/Cerebras/OpenRouter/Ollama)
├── Tools/      AriaTool implementations (files, web, apps, EventKit, computer-use…)
├── UI/         IslandView + MorphingBlob, IslandViewModel, SettingsView, OnboardingView
└── Utilities/  KeychainManager, PermissionsManager, AppSettings, Logger
```

Swift 6, SwiftUI + AppKit, structured concurrency (async/await + actors), MVVM. 166 unit
tests cover the model protocol, agent loop, tool declarations, autonomy, computer-use logic,
memory, voice chunking, and the wake/barge state machines.

## Privacy

Aria has no backend. Wake-word detection is on-device; your keys live in the Keychain;
screenshots are captured only on command and never written to disk; secure text fields are
hidden from her screen-context read by macOS. The only network calls are to the AI provider
you configured, with your own key.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — especially how to add a new tool.

## License

MIT.
