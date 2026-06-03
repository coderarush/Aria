# Aria — Open Source AI Agent for Mac

> Your personal AI agent that lives on your Mac. Not an assistant that answers
> questions — an agent that **takes actions**.

<!-- demo gif here -->

Aria is a native Swift/SwiftUI macOS app. Say **"Hey Aria"**, and a
Dynamic-Island-style pill drops from the notch, listens, speaks back, sees your
screen, and goes to work. It's built to be the most capable open-source AI agent
for the Mac — extensible, private, and fully under your control.

> **Status: v2.0.** All core subsystems are built and tested (64 tests): wake
> word → notch pill → screen → Gemini, the full tool system, dynamic tool
> generation, sub-agents, on-device behavioral learning, on-device voice,
> accent theming, Settings, and onboarding. See the [roadmap](#roadmap).

---

## Install

macOS (Apple Silicon or Intel). One line in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/coderarush/Aria/main/install.sh | bash
```

This builds Aria from source, installs it to `/Applications`, and registers a
login agent so it **auto-starts and runs in the background** — no terminal kept
open. Requires Xcode Command Line Tools (`xcode-select --install`). On first
launch, allow Microphone / Speech Recognition / Screen Recording, then open
Settings to add a free [Gemini API key](https://aistudio.google.com) and install
a free **Premium** voice from the Voice tab for the most natural speech.

## ✨ Features

- 🎙️ **"Hey Aria" wake word** — always-on, on-device (`SFSpeechRecognizer`), zero cloud listening
- 🟢 **Dynamic Island pill** — a notch-anchored surface that morphs: breathing dot → live waveform → response card; frosted material, accent-tinted
- 🔊 **On-device voice** — Aria speaks responses with an Apple voice; private, offline, no extra key
- 🎨 **Accent theming** — follow system, presets, or a custom color; applied live
- 😎 **Confident & charming** — a sharp personal-assistant personality, concise by design
- 👁️ **Screen vision** — captures your screen on command (never continuously) and sends it to the model
- 🧠 **Gemini brain** — `gemini-flash-latest`, vision-capable, structured-JSON agent protocol
- 🔐 **Private by design** — your own API key in the macOS Keychain, screenshots never written to disk, no servers
- 🧩 **Extensible** — clean `AriaTool` protocol, MVVM + async/await throughout

### Roadmap

| Subsystem | Status |
|---|---|
| Wake word + orb + screen + Gemini loop | ✅ v0.1 |
| Dynamic tool generation (Aria writes + runs + saves its own tools) | ✅ v0.2 |
| Tool system + registry (Shell, AppleScript, Files, Clipboard, Notify, OpenApp, Browser, WebSearch, WebFetch) | ✅ v0.3 |
| Sub-agents (Research, CodeWriter, TaskPlanner) | ✅ v0.4 |
| Behavioral learning & proactive automation | ✅ v0.5 |
| Onboarding + full Settings (General/API/Tools/Dynamic/Brain/Mirror) | ✅ v0.6 |
| Smart-mirror bridge (interface stub) | ✅ v0.6 |
| Metal-shader orb polish (runtime-compiled MSL glow/pulse/plasma) | ✅ v0.7 |
| Reliable wake/command capture (recognition restart fixes) | ✅ v1.0 |
| Aria redesign — notch pill (drops Metal), on-device voice, confident-and-charming persona, accent theming, full rename | ✅ v2.0 |

---

## Why Aria vs HeyClicky

| | HeyClicky | **Aria** |
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
git clone <your-repo-url> Aria
cd Aria
make build      # compile (SwiftPM)
make test       # run unit tests
make release    # assemble Aria.app (ad-hoc signed)
open .build/Aria.app
```

Requirements: **macOS 14+**, **Xcode 15+** (Swift 5.9+).

Prefer Xcode? `brew install xcodegen && make xcode` generates `Aria.xcodeproj`.

---

## Configuration — Gemini API key

Aria uses your own [Google AI Studio](https://aistudio.google.com/app/apikey)
key (free tier works).

- If a key exists at `~/Aria/.apikey`, Aria migrates it to the Keychain on
  first launch automatically.
- Otherwise, store it yourself:

```bash
security add-generic-password -s com.aria.agent -a gemini_api_key -w "YOUR_KEY"
```

The key lives in the macOS Keychain — never in plaintext, never sent anywhere
except Google's API.

---

## Permissions

On first run Aria requests:

- **Microphone** + **Speech Recognition** — required for the wake word
- **Screen Recording** — prompted on first capture; without it Aria degrades to text-only

Grant these in **System Settings → Privacy & Security**.

---

## Voice commands (today)

| Say | Aria does |
|---|---|
| "Hey Aria, what's on my screen?" | Captures screen, describes it |
| "Hey Aria, summarize this page" | Reads the screen, summarizes |
| "Hey Aria, dismiss" / "thanks Aria" | Hides the pill |

As the tool system lands, Aria will open apps, write files, send mail, run
code, search the web, and more.

---

## Architecture

```
Sources/Aria/
├── App/        AriaApp, AppDelegate (menu bar), AriaController (wiring)
├── Core/       WakeWordEngine, ScreenCaptureEngine, GeminiClient,
│               AgentOrchestrator, ConversationMemory, Models
├── UI/         IslandView, IslandViewModel (state machine), IslandPanel, NotchGeometry, WaveformView
└── Utilities/  KeychainManager, PermissionsManager, Logger
```

MVVM, structured concurrency (async/await + actors), no force-unwraps in
production paths.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — especially how to add a new tool.

## License

MIT — see [LICENSE](LICENSE).
