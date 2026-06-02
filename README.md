# Friday — Open Source AI Agent for Mac

> Your personal AI agent that lives on your Mac. Not an assistant that answers
> questions — an agent that **takes actions**.

<!-- demo gif here -->

Friday is a native Swift/SwiftUI macOS app. Say **"Hey Friday"**, a frosted-glass
orb materializes, listens, sees your screen, and goes to work. It's built to be
the most capable open-source AI agent for the Mac — extensible, private, and
fully under your control.

> **Status: early (v0.1, vertical slice).** The core spine works end to end —
> wake word → orb → screen capture → Gemini → response. The big subsystems
> (tools, dynamic tool generation, sub-agents, behavioral learning) are
> architected with seams and land in upcoming releases. See the [roadmap](#roadmap).

---

## ✨ Features

- 🎙️ **"Hey Friday" wake word** — always-on, on-device (`SFSpeechRecognizer`), zero cloud listening
- 🔮 **Living orb UI** — frosted glass, breathing pulse, mic waveform, state-aware glow; floats over any app
- 👁️ **Screen vision** — captures your screen on command (never continuously) and sends it to the model
- 🧠 **Gemini brain** — `gemini-1.5-flash`, vision-capable, structured-JSON agent protocol
- 🔐 **Private by design** — your own API key in the macOS Keychain, screenshots never written to disk, no servers
- 🧩 **Extensible** — clean `FridayTool` protocol, MVVM + async/await throughout

### Roadmap

| Subsystem | Status |
|---|---|
| Wake word + orb + screen + Gemini loop | ✅ v0.1 |
| Tool system (Shell, AppleScript, Files, Mail, Calendar, …) | 🔜 |
| Dynamic tool generation (Friday writes its own tools) | 🔜 |
| Sub-agents (Research, FileOrganizer, CodeWriter, …) | 🔜 |
| Behavioral learning & proactive automation | 🔜 |
| Onboarding + full Settings | 🔜 |
| Metal-shader orb polish | 🔜 |
| Smart-mirror bridge | 🔜 (stub) |

---

## Why Friday vs HeyClicky

| | HeyClicky | **Friday** |
|---|---|---|
| Takes real actions | Limited | ✅ Tool + sub-agent system |
| Writes its own tools at runtime | ❌ | ✅ (planned, architected) |
| Learns your habits & automates | ❌ | ✅ (planned, architected) |
| Open source | ❌ | ✅ MIT |
| Your own API key, no servers | — | ✅ |
| Screen vision | — | ✅ ScreenCaptureKit |

---

## Install

### Build from source

```bash
git clone <your-repo-url> Friday
cd Friday
make build      # compile (SwiftPM)
make test       # run unit tests
make release    # assemble Friday.app (ad-hoc signed)
open .build/Friday.app
```

Requirements: **macOS 14+**, **Xcode 15+** (Swift 5.9+).

Prefer Xcode? `brew install xcodegen && make xcode` generates `Friday.xcodeproj`.

---

## Configuration — Gemini API key

Friday uses your own [Google AI Studio](https://aistudio.google.com/app/apikey)
key (free tier works).

- If a key exists at `~/Friday/.apikey`, Friday migrates it to the Keychain on
  first launch automatically.
- Otherwise, store it yourself:

```bash
security add-generic-password -s com.friday.agent -a gemini_api_key -w "YOUR_KEY"
```

The key lives in the macOS Keychain — never in plaintext, never sent anywhere
except Google's API.

---

## Permissions

On first run Friday requests:

- **Microphone** + **Speech Recognition** — required for the wake word
- **Screen Recording** — prompted on first capture; without it Friday degrades to text-only

Grant these in **System Settings → Privacy & Security**.

---

## Voice commands (today)

| Say | Friday does |
|---|---|
| "Hey Friday, what's on my screen?" | Captures screen, describes it |
| "Hey Friday, summarize this page" | Reads the screen, summarizes |
| "Hey Friday, dismiss" / "thanks Friday" | Hides the orb |

As the tool system lands, Friday will open apps, write files, send mail, run
code, search the web, and more.

---

## Architecture

```
Sources/Friday/
├── App/        FridayApp, AppDelegate (menu bar), FridayController (wiring)
├── Core/       WakeWordEngine, ScreenCaptureEngine, GeminiClient,
│               AgentOrchestrator, ConversationMemory, Models
├── UI/         OrbView, OrbViewModel (state machine), ResponseCard, WaveformView
└── Utilities/  KeychainManager, PermissionsManager, Logger
```

MVVM, structured concurrency (async/await + actors), no force-unwraps in
production paths.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — especially how to add a new tool.

## License

MIT — see [LICENSE](LICENSE).
