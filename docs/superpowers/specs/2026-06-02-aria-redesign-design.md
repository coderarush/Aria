# Aria — Redesign Design Spec

**Date:** 2026-06-02
**Status:** Approved (pending final spec review)
**Supersedes look & branding of:** Friday v1.0.0

## Summary

Rebrand and redesign the assistant currently called **Friday** into **Aria**: a
confident, charming personal assistant that lives in the Mac's notch as a
Dynamic-Island-style morphing pill, speaks responses aloud with an on-device
voice, and supports accent-color theming. The redesign replaces the Metal
shader "orb" with a clean, minimal SwiftUI surface. The wake → command → Gemini
→ action pipeline (recently fixed) is reskinned and renamed, **not** changed in
behavior.

## Goals

- Rename Friday → **Aria** everywhere (full rename, including bundle id and repo).
- Replace the Metal orb with a minimal, "Apple-native" notch pill.
- Dynamic-Island placement: top-center, hugging the notch.
- On-device voice (text-to-speech) for responses.
- Confident & charming personality.
- Accent-color customization.

## Non-Goals (YAGNI)

- Cloud/neural TTS (on-device Apple voice only this round).
- Full surface theming/skins — only the **accent** color is customizable; the
  surface stays neutral material.
- Bottom-of-screen or menu-bar-dropdown placement (notch only).
- Changes to the speech-recognition / orchestration logic (reskin + rename only).
- Dragging/repositioning the pill (it is pinned to the notch).

## Decisions (locked with user)

| Topic | Decision |
|-------|----------|
| Name | **Aria**, wake word "Hey Aria" |
| Placement | Notch pill, top-center, Dynamic-Island morph |
| UI approach | Morphing SwiftUI pill; **drop Metal** |
| Voice | On-device `AVSpeechSynthesizer`, default on |
| Personality | Confident & charming (JARVIS-ish, not campy) |
| Theming | Accent only: follow-system (default) / presets / custom |
| Rename depth | **Full** — bundle id `com.aria.assistant`, launch agent, repo rename |

---

## Section 1 — Module map

**Removed (the vibe-coded layer):**
- `OrbMetalView.swift` + Metal shader orb; `OrbShaderTests.swift`.
- `OrbView.swift`, `ResponseCard.swift` (folded into Island views).

**New UI module (`Sources/Aria/UI/`):**
- `IslandPanel.swift` — borderless, non-activating `NSPanel`, anchored
  top-center hugging the notch; click-through when idle (never steals focus or
  blocks the menu bar).
- `NotchGeometry.swift` — finds the notch via `NSScreen.safeAreaInsets` /
  `auxiliaryTopLeftArea`; computes pill frame; falls back to top-center on
  notchless displays.
- `IslandView.swift` — SwiftUI morphing pill; swaps layout by state.
- `IslandViewModel.swift` — evolves `OrbViewModel`: states
  `idle / listening / thinking / responding / error`, audio level, response
  text, theme accent, auto-collapse timer.
- `WaveformView.swift` — kept, restyled for the listening state.

**New core/util:**
- `Core/VoiceEngine.swift` — `AVSpeechSynthesizer` wrapper.
- `Utilities/Theme.swift` — accent color + presets, light/dark aware.

**Edited:**
- `WakeWordEngine` — wake variants → "hey aria" family.
- `GeminiClient` — system prompt → Aria persona (message phrasing only).
- `AppSettings` + `SettingsView` — accent picker + voice settings.
- `FridayController` → `AriaController` — drives `IslandViewModel`; pipeline
  behavior unchanged.

The speech-recognition engine internals stay as-is.

---

## Section 2 — The notch pill (states & morph)

One surface glued to the notch's bottom edge; grows downward and outward with a
spring animation, corners rounded to continue the notch curve.

| State | Shape | Content |
|-------|-------|---------|
| Idle | Thin sliver hugging the notch (~notch height). **Click-through.** | Faint accent "breathing" dot, or nothing. |
| Listening | Expands wider + a bit taller below the notch. | Live waveform (accent-tinted) reacting to voice. |
| Thinking | Holds width. | Slow accent shimmer sweep (no spinner). |
| Responding | Morphs into a rounded card below the notch. | Aria's text (concise), accent keyline; small waveform pulse while speaking. Auto-collapses ~8s. |
| Error | Same card, dismisses faster (~3s). | Brief message. |

**Look:** `.ultraThinMaterial` surface, subtle shadow, light/dark adaptive.
Color appears only on accents (waveform, breathing dot, keyline, shimmer); the
surface stays neutral. That neutrality is what keeps it minimal.

**Interaction:**
- Idle = click-through (`ignoresMouseEvents`).
- Expanded card: click anywhere to dismiss; otherwise voice/wake drives it. No
  dragging.
- Manual summon stays on the existing menu-bar item + hotkey.

**Sizing (tunable):** collapsed ≈ 200×34, listening ≈ 320×64, response card ≈
380×140; spring response ≈ 0.4, high damping for a calm morph. Waveform feeds
off the existing `onAudioLevel` callback — no new audio plumbing.

---

## Section 3 — Character & voice

**Personality (Aria — confident & charming).** Lives in `GeminiClient`'s system
prompt. A sharp personal assistant who has it handled: warm, a little charm, the
occasional clever aside, never campy. **Concise by mandate** — 1–2 sentences.
Action confirmations crisp ("On it." / "Done — Spotify's up."). First-person,
direct, no corporate filler, no emoji spam.

**Hard constraint:** the structured **JSON action protocol is unchanged** — the
orchestrator depends on it. Personality changes only the phrasing of the
`message` field, never the tool-output shape.

**Voice (`Core/VoiceEngine.swift`).** Wraps `AVSpeechSynthesizer`; speaks Aria's
`message` on response. Default on.
- Picks a premium/enhanced Apple voice if installed, else best default.
- Settings: voice on/off, voice picker (installed enhanced/premium voices),
  speaking rate.
- Speaks clean text — strips markdown/asterisks/URLs from `message`.

**Feedback prevention (key detail):** the mic is always listening, so while Aria
speaks, `VoiceEngine` suspends wake detection (`wakeEngine.isSuspended = true`);
its delegate's `didFinish` resumes it. Reuses the existing suspend flag — no new
audio routing.

---

## Section 4 — Color theming

**`Utilities/Theme.swift`** — single source for the accent color; resolves a
SwiftUI `Color`; light/dark aware.

**Customizable:** the accent only (waveform, breathing dot, shimmer, keyline,
response accent). Surface stays neutral material in every theme.

**Settings options:**
- **Follow system accent** (default) — uses `controlAccentColor`.
- **Presets** — Graphite, Blue, Teal, Violet, Amber, Rose, Green.
- **Custom** — `ColorPicker` well for any color.

**Plumbing:** `AppSettings` persists the choice (preset id or hex) in
`UserDefaults`; `Theme` is `@Published`, so changing it in `SettingsView` updates
the pill live. `IslandViewModel` reads the accent and passes it to the views.
The picker shows a live pill preview; accent sits on neutral material so it stays
legible in light and dark.

---

## Section 5 — Full rename mechanics

**Code & target:**
- `Package.swift` target/product `Friday`→`Aria`; dirs `Sources/Friday/`→
  `Sources/Aria/`, `Tests/FridayTests/`→`Tests/AriaTests/`.
- All `Friday`/`friday` symbols → `Aria`/`aria`. Trace path `/tmp/friday.log`→
  `/tmp/aria.log`.
- `WakeWordEngine` variants → "hey aria" family (+ mishearings).

**App identity:**
- `Info.plist`: `CFBundleName`/`CFBundleExecutable`→Aria,
  `CFBundleIdentifier` `com.friday.assistant`→`com.aria.assistant`, usage
  strings → "Aria needs…".
- `Friday.entitlements`→`Aria.entitlements`; `Makefile` `APP_NAME`, signing
  identity `Friday Self-Signed`→`Aria Self-Signed`, bundle paths.

**System integration:**
- Launch agent: label/plist `com.friday.assistant`→`com.aria.assistant`, path →
  `Aria.app`. Cleanly `launchctl unload` + delete old plist so two agents don't
  run.
- Remove old `~/Applications/Friday.app`.
- New bundle id ⇒ macOS re-prompts mic + screen-recording **once**; re-run
  `make cert` so "Aria Self-Signed" makes grants persist across rebuilds.

**GitHub:** rename repo `coderarush/Friday`→`coderarush/Aria` (API); update local
remote. GitHub auto-redirects the old URL; v1.0 tag/release carry over.

**Docs:** README / CONTRIBUTING / app references → Aria.

---

## Testing

- `swift build` + `swift test` green after rename (update test target + any
  "Friday" string assertions).
- New unit tests:
  - `NotchGeometry` — frame math, notch vs notchless.
  - `Theme` — preset / hex / follow-system resolution.
  - `VoiceEngine` — markdown→speech stripping.
  - `IslandViewModel` — state transitions.
  - `OrbShaderTests` deleted.
- Manual smoke: build `Aria.app`, grant perms, verify notch pill morphs, "Hey
  Aria" wakes, command runs, **voice speaks**, **multiple wakes** (guards the
  cascade fix from v1.0), live color change.

## Risks / call-outs

- **Two outward/irreversible steps confirmed with user at execution time, not
  silently:** GitHub repo rename; deleting old `Friday.app` / launch agent.
- New bundle id loses prior TCC grants and the stable signing identity — expected;
  mitigated by re-prompt + `make cert`.
- Launch-agent swap must fully remove the old agent to avoid double-running.

## Suggested implementation staging (for the plan)

1. Full rename, keep build + tests green (no behavior change).
2. Notch pill UI (drop Metal) + `NotchGeometry`.
3. Voice engine + feedback suspend.
4. Personality system prompt.
5. Accent theming + Settings.
6. System integration (launch agent, app cleanup) + repo rename.
