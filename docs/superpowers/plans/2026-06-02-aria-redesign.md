# Aria Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand Friday → **Aria** and replace the Metal orb with a minimal Dynamic-Island notch pill that speaks responses (on-device voice), has a confident-and-charming personality, and supports accent-color theming.

**Architecture:** Reskin + rename only — the wake → command → Gemini → action pipeline is untouched in behavior. A new SwiftUI `IslandView` (morphing pill in an `NSPanel` pinned to the notch) replaces the orb. New `VoiceEngine` (AVSpeechSynthesizer) speaks responses and suspends wake detection while talking. New `Theme` drives a single accent color. Renamed across code, bundle id, launch agent, and GitHub repo.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI, AppKit (`NSPanel`), AVFoundation (`AVSpeechSynthesizer`), Speech, XCTest.

**Reference spec:** `docs/superpowers/specs/2026-06-02-aria-redesign-design.md`

**Build/test commands:** `swift build` and `swift test` from repo root. The renamed test target is `AriaTests`.

**Phasing:** Each phase ends with `swift build` + `swift test` green. Phases are sequential: 1 (rename) must complete before 2–5; 6 (system integration + repo rename) is last and gated on user confirmation.

---

## Phase 1 — Full rename Friday → Aria (keep green)

### Task 1.1: Rename target, dirs, and symbols

**Files:**
- Modify: `Package.swift`
- Move: `Sources/Friday/` → `Sources/Aria/`, `Tests/FridayTests/` → `Tests/AriaTests/`
- Modify: all `.swift` files containing `Friday`/`friday` symbols

- [ ] **Step 1: Move the source and test directories with git**

```bash
cd ~/Desktop/Friday
git mv Sources/Friday Sources/Aria
git mv Tests/FridayTests Tests/AriaTests
```

- [ ] **Step 2: Rewrite Package.swift**

Replace the whole file with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aria",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Aria", targets: ["Aria"])
    ],
    targets: [
        .executableTarget(
            name: "Aria",
            path: "Sources/Aria"
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["Aria"],
            path: "Tests/AriaTests"
        )
    ]
)
```

- [ ] **Step 3: Rename code symbols across the renamed dirs**

Renames the user-facing/product symbols while leaving the `FridayResponse` model name for Task 1.3 (it is referenced widely; do it separately to keep diffs reviewable). Run:

```bash
cd ~/Desktop/Friday
# Type/struct/class renames that are safe and unambiguous:
grep -rl 'FridayApp' Sources Tests | xargs sed -i '' 's/FridayApp/AriaApp/g'
grep -rl 'FridayController' Sources Tests | xargs sed -i '' 's/FridayController/AriaController/g'
# Log subsystem + any "Friday" UI strings:
grep -rl '"com.friday' Sources | xargs sed -i '' 's/com\.friday/com.aria/g'
```

- [ ] **Step 4: Rename the app entry filenames**

```bash
cd ~/Desktop/Friday/Sources/Aria
git mv App/FridayApp.swift App/AriaApp.swift
git mv App/FridayController.swift App/AriaController.swift
```

- [ ] **Step 5: Build to find remaining references**

Run: `swift build`
Expected: compile errors listing any remaining `Friday` symbol references (e.g. inside `AppDelegate.swift`, `@main struct`). Fix each by replacing `Friday` → `Aria` in the symbol, leaving `FridayResponse` (model) alone for now. Re-run until `Build complete!`.

- [ ] **Step 6: Run tests**

Run: `swift test`
Expected: `Executed N tests, with 0 failures`. If a test references `FridayApp`/`FridayController`, it was renamed by Step 3; if any assert a literal `"Friday"` string, update to `"Aria"`.

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/Friday
git add -A
git commit -m "refactor: rename target and app symbols Friday -> Aria"
```

### Task 1.2: Rename the FridayResponse model

**Files:**
- Modify: `Sources/Aria/Core/Models.swift` and every file referencing `FridayResponse`

- [ ] **Step 1: Rename the model everywhere**

```bash
cd ~/Desktop/Friday
grep -rl 'FridayResponse' Sources Tests | xargs sed -i '' 's/FridayResponse/AriaResponse/g'
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!` (the rename is global, so no dangling references).

- [ ] **Step 3: Run tests**

Run: `swift test`
Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename FridayResponse -> AriaResponse"
```

### Task 1.3: Rename bundle, entitlements, wake words, trace path, usage strings

**Files:**
- Modify: `Resources/Info.plist`
- Move + modify: `Resources/Friday.entitlements` → `Resources/Aria.entitlements`
- Modify: `Makefile`
- Modify: `Sources/Aria/Core/WakeWordEngine.swift`
- Modify: `Sources/Aria/Utilities/Logger.swift` (trace path)

- [ ] **Step 1: Rewrite Info.plist**

Replace the file with (note bundle id `com.aria.agent`, display name Aria, Aria usage strings):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Aria</string>
    <key>CFBundleDisplayName</key>
    <string>Aria</string>
    <key>CFBundleIdentifier</key>
    <string>com.aria.agent</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Aria</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aria listens for the "Hey Aria" wake phrase on-device.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Aria transcribes your voice commands on-device to understand what you need.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Aria captures your screen only when you issue a command, to see what you are working on.</string>
</dict>
</plist>
```

- [ ] **Step 2: Rename the entitlements file**

```bash
cd ~/Desktop/Friday
git mv Resources/Friday.entitlements Resources/Aria.entitlements
```

- [ ] **Step 3: Update the Makefile**

In `Makefile`, replace these values (exact substitutions):
- `APP_NAME    := Friday` → `APP_NAME    := Aria`
- `Resources/Info.plist` stays (path unchanged).
- `--entitlements Resources/Friday.entitlements` → `--entitlements Resources/Aria.entitlements`
- Signing identity grep `"Friday Self-Signed"` → `"Aria Self-Signed"` (both the `grep -q` and the `echo`) and the `SIGN_ID` default echo string.
- `cert` target: certificate CN `/CN=Friday Self-Signed` → `/CN=Aria Self-Signed`, and the grep `"Friday Self-Signed"` → `"Aria Self-Signed"`.

Run after editing:
```bash
cd ~/Desktop/Friday
grep -n "Friday" Makefile || echo "no Friday refs left in Makefile"
```
Expected: `no Friday refs left in Makefile`.

- [ ] **Step 4: Update wake variants**

In `Sources/Aria/Core/WakeWordEngine.swift`, replace the `wakeVariants` array:

```swift
    private let wakeVariants = ["hey aria", "hey arya", "hey aria's",
                               "hey, aria", "aria", "hey ariel"]
```

- [ ] **Step 5: Update the trace log path**

In `Sources/Aria/Utilities/Logger.swift`, change the two occurrences of `/tmp/friday.log` to `/tmp/aria.log`.

- [ ] **Step 6: Build, test, commit**

```bash
cd ~/Desktop/Friday
swift build && swift test
git add -A
git commit -m "refactor: rename bundle id, entitlements, wake words, trace path to Aria"
```
Expected: `Build complete!` and `0 failures` before committing.

---

## Phase 2 — Notch pill UI (drop Metal)

### Task 2.1: NotchGeometry (pure, TDD)

**Files:**
- Create: `Sources/Aria/UI/NotchGeometry.swift`
- Test: `Tests/AriaTests/NotchGeometryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import Aria

final class NotchGeometryTests: XCTestCase {
    func testPanelFrameIsHorizontallyCenteredAndTopPinned() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900) // bottom-left origin
        let size = CGSize(width: 320, height: 64)
        let frame = NotchGeometry.panelFrame(screenFrame: screen, size: size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.5) // top pinned
        XCTAssertEqual(frame.width, 320, accuracy: 0.5)
        XCTAssertEqual(frame.height, 64, accuracy: 0.5)
    }

    func testHasNotch() {
        XCTAssertTrue(NotchGeometry.hasNotch(topInset: 38))
        XCTAssertFalse(NotchGeometry.hasNotch(topInset: 0))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotchGeometryTests`
Expected: FAIL — "no such module member" / `NotchGeometry` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation
import CoreGraphics

/// Pure geometry for placing the Island pill at top-center / the notch.
/// Kept free of AppKit so it is unit-testable; the panel passes real
/// NSScreen values in at runtime.
enum NotchGeometry {
    /// Frame for the panel given the screen frame (bottom-left origin) and the
    /// desired pill size. The pill's TOP edge is pinned to the screen top so it
    /// grows downward as it expands; it is centered horizontally under the notch.
    static func panelFrame(screenFrame: CGRect, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A display has a notch when its top safe-area inset is non-zero.
    static func hasNotch(topInset: CGFloat) -> Bool { topInset > 0 }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Aria/UI/NotchGeometry.swift Tests/AriaTests/NotchGeometryTests.swift
git commit -m "feat: NotchGeometry for top-center/notch pill placement"
```

### Task 2.2: IslandViewModel (TDD)

**Files:**
- Create: `Sources/Aria/UI/IslandViewModel.swift`
- Test: `Tests/AriaTests/IslandViewModelTests.swift`
- Delete (later, Task 2.5): `Sources/Aria/UI/OrbViewModel.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Aria

@MainActor
final class IslandViewModelTests: XCTestCase {
    func testListeningMakesVisible() {
        let vm = IslandViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isVisible)
        vm.beginListening()
        XCTAssertEqual(vm.state, .listening)
        XCTAssertTrue(vm.isVisible)
    }

    func testResponseSetsTextAndState() {
        let vm = IslandViewModel()
        vm.beginListening()
        vm.showResponse("On it.")
        XCTAssertEqual(vm.state, .responding)
        XCTAssertEqual(vm.responseText, "On it.")
    }

    func testDismissHidesAndClears() {
        let vm = IslandViewModel()
        vm.beginListening()
        vm.showResponse("Done.")
        vm.dismiss()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isVisible)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter IslandViewModelTests`
Expected: FAIL — `IslandViewModel` undefined.

- [ ] **Step 3: Implement**

```swift
import SwiftUI
import Combine

/// State machine + presentation state for the Island pill. Mirrors the old
/// OrbViewModel but with idle/listening/thinking/responding/error states and an
/// accent color for theming.
@MainActor
final class IslandViewModel: ObservableObject {

    enum State: Equatable { case idle, listening, thinking, responding, error }

    @Published private(set) var state: State = .idle
    @Published var responseText: String = ""
    @Published var audioLevel: Float = 0
    @Published var isVisible: Bool = false
    @Published var accent: Color = .accentColor

    /// Fired when the pill wants the hosting panel to show/hide.
    var onVisibilityChange: ((Bool) -> Void)?

    private var dismissTask: Task<Void, Never>?
    var autoDismiss: TimeInterval = 8

    func beginListening() {
        cancelDismiss()
        responseText = ""
        setState(.listening)
        setVisible(true)
    }

    func beginThinking() { cancelDismiss(); setState(.thinking) }

    func showResponse(_ text: String) {
        responseText = text
        setState(.responding)
        scheduleDismiss()
    }

    func showError(_ text: String = "") {
        responseText = text
        setState(.error)
        scheduleDismiss(after: 3)
    }

    func dismiss() {
        cancelDismiss()
        responseText = ""
        setState(.idle)
        setVisible(false)
    }

    func updateAudioLevel(_ level: Float) { audioLevel = level }

    private func setState(_ new: State) { guard state != new else { return }; state = new }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        onVisibilityChange?(visible)
    }

    private func scheduleDismiss(after seconds: TimeInterval? = nil) {
        cancelDismiss()
        let delay = seconds ?? autoDismiss
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    private func cancelDismiss() { dismissTask?.cancel(); dismissTask = nil }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter IslandViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Aria/UI/IslandViewModel.swift Tests/AriaTests/IslandViewModelTests.swift
git commit -m "feat: IslandViewModel state machine"
```

### Task 2.3: IslandView + subviews (morphing pill)

**Files:**
- Create: `Sources/Aria/UI/IslandView.swift`

No unit test (SwiftUI rendering — verified manually in Task 2.5).

- [ ] **Step 1: Implement IslandView**

```swift
import SwiftUI

/// The Dynamic-Island pill. One surface whose size/content morph by state.
/// Pinned at the top; grows downward. Color appears only on accents; the
/// surface stays neutral `.ultraThinMaterial`.
struct IslandView: View {
    @ObservedObject var viewModel: IslandViewModel

    private var size: CGSize {
        switch viewModel.state {
        case .idle:       return CGSize(width: 200, height: 34)
        case .listening:  return CGSize(width: 320, height: 64)
        case .thinking:   return CGSize(width: 320, height: 64)
        case .responding, .error: return CGSize(width: 380, height: 140)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(viewModel.accent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

            content
                .padding(.horizontal, 16)
        }
        .frame(width: size.width, height: size.height)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.state)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onTapGesture { if viewModel.state == .responding || viewModel.state == .error { viewModel.dismiss() } }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle:
            BreathingDot(accent: viewModel.accent)
        case .listening:
            WaveformView(level: viewModel.audioLevel, color: viewModel.accent)
                .frame(height: 28)
        case .thinking:
            ShimmerBar(accent: viewModel.accent)
        case .responding, .error:
            Text(viewModel.responseText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Faint accent dot that breathes while idle.
private struct BreathingDot: View {
    let accent: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(accent.opacity(on ? 0.8 : 0.3))
            .frame(width: 6, height: 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Indeterminate accent shimmer sweep for the thinking state.
private struct ShimmerBar: View {
    let accent: Color
    @State private var x: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(LinearGradient(colors: [.clear, accent, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * 0.4, height: 4)
                .offset(x: x * geo.size.width)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { x = 1 }
                }
        }
        .frame(height: 8)
    }
}
```

- [ ] **Step 2: Build (compile check only)**

Run: `swift build`
Expected: `Build complete!` (IslandView not yet wired into the panel; this just confirms it compiles).

- [ ] **Step 3: Commit**

```bash
git add Sources/Aria/UI/IslandView.swift
git commit -m "feat: IslandView morphing pill + subviews"
```

### Task 2.4: IslandPanel (NSPanel at the notch)

**Files:**
- Create: `Sources/Aria/UI/IslandPanel.swift`

- [ ] **Step 1: Implement the panel**

```swift
import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the Island pill at the top-center
/// of the main screen, hugging the notch. Floats above other windows; click-
/// through is toggled by the controller based on visibility.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Position centered on the main screen, top edge pinned under the notch.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame, size: self.frame.size)
        setFrame(frame, display: true)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Aria/UI/IslandPanel.swift
git commit -m "feat: IslandPanel hosting the pill at the notch"
```

### Task 2.5: Wire AriaController to the Island; remove the orb

**Files:**
- Modify: `Sources/Aria/App/AriaController.swift`
- Delete: `Sources/Aria/UI/OrbView.swift`, `Sources/Aria/UI/OrbViewModel.swift`, `Sources/Aria/UI/OrbMetalView.swift`, `Sources/Aria/UI/ResponseCard.swift`
- Delete: `Tests/AriaTests/OrbShaderTests.swift`

- [ ] **Step 1: Repoint the controller**

In `AriaController.swift`:
1. Replace the property `private var orbViewModel = OrbViewModel()` (or equivalent) with:
   ```swift
   let islandViewModel = IslandViewModel()
   ```
2. Replace every `orbViewModel.` call with `islandViewModel.` and map the states: `beginListening()`, `beginThinking()`, `showResponse(_:)`, `showError(_:)`, `dismiss()`, `updateAudioLevel(_:)` all exist on `IslandViewModel` with the same names. Replace any `.state == .listening` checks (the `onCommandEmpty` guard) with `islandViewModel.state == .listening`.
3. In `setupPanel()` replace the body with:
   ```swift
   private func setupPanel() {
       let panel = IslandPanel()
       let host = NSHostingView(rootView: IslandView(viewModel: islandViewModel))
       host.frame = panel.contentLayoutRect
       host.autoresizingMask = [.width, .height]
       panel.contentView = host
       self.panel = panel

       islandViewModel.onVisibilityChange = { [weak self] visible in
           self?.setPanelVisible(visible)
           if !visible {
               self?.wakeEngine.isSuspended = false
               Log.trace("island hidden → wake re-armed (isSuspended=false)")
           }
       }
   }
   ```
4. Change the `panel` property type to `IslandPanel?`.
5. Replace `setPanelVisible` / `positionPanel` bodies:
   ```swift
   private func setPanelVisible(_ visible: Bool) {
       guard let panel else { return }
       if visible {
           panel.reposition()
           panel.ignoresMouseEvents = false
           panel.orderFrontRegardless()
       } else {
           panel.ignoresMouseEvents = true   // click-through when idle
           panel.orderOut(nil)
       }
   }
   ```
   Delete the old `positionPanel(_:)` method (replaced by `panel.reposition()`).

- [ ] **Step 2: Delete the orb files**

```bash
cd ~/Desktop/Friday
git rm Sources/Aria/UI/OrbView.swift Sources/Aria/UI/OrbViewModel.swift Sources/Aria/UI/OrbMetalView.swift Sources/Aria/UI/ResponseCard.swift
git rm Tests/AriaTests/OrbShaderTests.swift
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`. Fix any remaining `Orb*` references the compiler flags (e.g., `OrbPanel` class if defined inside the controller — replace with `IslandPanel`; `OrbView`/`OrbViewModel` references; the `OrbPosition`/`OrbSize` settings are used only by the old GeneralSettingsTab which Phase 5 rewrites — leave them for now, they still compile).

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: `0 failures` (OrbShaderTests removed; IslandViewModelTests + NotchGeometryTests pass).

- [ ] **Step 5: Manual smoke**

```bash
make run
```
Verify: a pill appears top-center/at the notch; say "Hey Aria, open Spotify" → pill morphs (waveform → shimmer → text card), Spotify opens, card collapses; say "Hey Aria" again → it wakes again (guards the v1.0 cascade fix). Quit with the menu-bar item.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: replace orb with Island pill; remove Metal renderer"
```

---

## Phase 3 — Voice (on-device)

### Task 3.1: VoiceEngine (TDD for text cleaning)

**Files:**
- Create: `Sources/Aria/Core/VoiceEngine.swift`
- Test: `Tests/AriaTests/VoiceEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Aria

final class VoiceEngineTests: XCTestCase {
    func testStripsMarkdownAndUrls() {
        let input = "Opening **Spotify** for you.\n\n**open_app** → Opened https://open.spotify.com"
        let out = VoiceEngine.spokenText(from: input)
        XCTAssertFalse(out.contains("*"))
        XCTAssertFalse(out.contains("→"))
        XCTAssertFalse(out.contains("http"))
        XCTAssertTrue(out.contains("Opening Spotify for you"))
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(VoiceEngine.spokenText(from: "Done.\n\n\nNext."), "Done. Next.")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(VoiceEngine.spokenText(from: "   \n  "), "")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VoiceEngineTests`
Expected: FAIL — `VoiceEngine` undefined.

- [ ] **Step 3: Implement**

```swift
import AVFoundation

/// On-device text-to-speech for Aria's spoken responses. Strips markdown so the
/// synthesizer reads clean prose, and notifies start/finish so the controller
/// can mute wake detection while Aria speaks (preventing self-triggering).
@MainActor
final class VoiceEngine: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    var enabled = true
    var voiceIdentifier: String?
    var rate: Float = 0.5 * (AVSpeechUtteranceMaximumSpeechRate + AVSpeechUtteranceMinimumSpeechRate)

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ message: String) {
        guard enabled else { return }
        let clean = Self.spokenText(from: message)
        guard !clean.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: clean)
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = v
        } else {
            utterance.voice = Self.preferredVoice()
        }
        utterance.rate = rate
        onStart?()
        synth.speak(utterance)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    /// Prefer an enhanced/premium en-US voice; fall back to the default en-US.
    static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let enUS = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        if let enhanced = enUS.first(where: { $0.quality == .premium })
            ?? enUS.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Remove markdown emphasis, code ticks, arrows, and URLs; collapse whitespace.
    static func spokenText(from message: String) -> String {
        var s = message
        // Strip bare URLs.
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        // Strip markdown link syntax, keeping the label: [label](url) -> label
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Remove emphasis/code characters and arrows.
        for token in ["**", "*", "`", "→", "_", "#"] {
            s = s.replacingOccurrences(of: token, with: " ")
        }
        // Collapse all whitespace runs to single spaces.
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter VoiceEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Aria/Core/VoiceEngine.swift Tests/AriaTests/VoiceEngineTests.swift
git commit -m "feat: VoiceEngine (on-device TTS) with markdown stripping"
```

### Task 3.2: Speak responses + suspend wake while speaking

**Files:**
- Modify: `Sources/Aria/App/AriaController.swift`

- [ ] **Step 1: Add the voice engine and wire it**

In `AriaController.swift`:
1. Add property: `private let voice = VoiceEngine()`
2. In `init`/`setup` (where other engines are wired), add:
   ```swift
   voice.onStart = { [weak self] in self?.wakeEngine.isSuspended = true }
   voice.onFinish = { [weak self] in
       guard let self else { return }
       // Resume listening only if the orb has gone idle; otherwise the normal
       // visibility handler will re-arm on dismiss.
       if !self.islandViewModel.isVisible { self.wakeEngine.isSuspended = false }
   }
   ```
3. In `handleCommand`, after `islandViewModel.showResponse(response.message)` (success branch), add:
   ```swift
   voice.speak(response.message)
   ```
   Do not speak on the `showError` branch.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`.

- [ ] **Step 3: Manual smoke**

```bash
make run
```
Verify: "Hey Aria, what time is it" → Aria speaks the answer; while she speaks, saying "Aria" does not re-trigger; after she finishes and the card collapses, a fresh "Hey Aria" wakes again.

- [ ] **Step 4: Commit**

```bash
git add Sources/Aria/App/AriaController.swift
git commit -m "feat: speak responses and suspend wake while speaking"
```

### Task 3.3: Voice settings (enable, voice, rate)

**Files:**
- Modify: `Sources/Aria/Utilities/AppSettings.swift`
- Modify: `Sources/Aria/App/AriaController.swift`
- Modify: `Sources/Aria/UI/SettingsView.swift`

- [ ] **Step 1: Add settings properties**

In `AppSettings.swift`, add published properties + keys (follow the existing `didSet` pattern):

```swift
    @Published var voiceEnabled: Bool { didSet { defaults.set(voiceEnabled, forKey: K.voiceEnabled) } }
    @Published var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: K.voiceIdentifier) } }
    @Published var voiceRate: Double { didSet { defaults.set(voiceRate, forKey: K.voiceRate) } }
```

In `init`, after the existing assignments:

```swift
        voiceEnabled = defaults.object(forKey: K.voiceEnabled) as? Bool ?? true
        voiceIdentifier = defaults.string(forKey: K.voiceIdentifier) ?? ""
        voiceRate = defaults.object(forKey: K.voiceRate) as? Double ?? 0.5
```

In `enum K`:

```swift
        static let voiceEnabled = "app.voiceEnabled"
        static let voiceIdentifier = "app.voiceIdentifier"
        static let voiceRate = "app.voiceRate"
```

- [ ] **Step 2: Apply settings to the voice engine**

In `AriaController.swift`, where the controller reads settings (or in `setup`), apply and observe:

```swift
    private func applyVoiceSettings() {
        let s = AppSettings.shared
        voice.enabled = s.voiceEnabled
        voice.voiceIdentifier = s.voiceIdentifier.isEmpty ? nil : s.voiceIdentifier
        voice.rate = Float(s.voiceRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) + AVSpeechUtteranceMinimumSpeechRate
    }
```

Call `applyVoiceSettings()` once during setup, and re-apply right before `voice.speak(...)` in `handleCommand` so changes take effect live. Add `import AVFoundation` at the top of `AriaController.swift` if not present.

- [ ] **Step 3: Add a Voice tab to Settings**

In `SettingsView.swift`, add a tab item in the `TabView`:

```swift
            VoiceSettingsTab()
                .tabItem { Label("Voice", systemImage: "speaker.wave.2") }
```

And the view:

```swift
struct VoiceSettingsTab: View {
    @StateObject private var settings = AppSettings.shared
    private let voices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .sorted { $0.name < $1.name }

    var body: some View {
        Form {
            Toggle("Speak responses aloud", isOn: $settings.voiceEnabled)
            Picker("Voice", selection: $settings.voiceIdentifier) {
                Text("Automatic (best installed)").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name) (\(v.quality == .premium ? "Premium" : v.quality == .enhanced ? "Enhanced" : "Default"))")
                        .tag(v.identifier)
                }
            }
            HStack {
                Text("Speaking rate")
                Slider(value: $settings.voiceRate, in: 0...1, step: 0.05)
            }
            Text("Voices are on-device. Add Premium/Enhanced voices in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

Add `import AVFoundation` at the top of `SettingsView.swift`.

- [ ] **Step 4: Build, test, manual, commit**

```bash
swift build && swift test
make run   # toggle voice off in Settings → Voice; confirm Aria goes silent; pick a voice; confirm it changes
git add -A
git commit -m "feat: voice settings (enable, voice, rate)"
```

---

## Phase 4 — Personality (Aria persona)

### Task 4.1: Rewrite the system prompt

**Files:**
- Modify: `Sources/Aria/Core/GeminiClient.swift`
- Test: `Tests/AriaTests/GeminiClientTests.swift` (extend)

- [ ] **Step 1: Write the failing test**

Add to `GeminiClientTests.swift`:

```swift
    func testSystemPromptIsAriaAndKeepsSchema() {
        let p = GeminiClient.systemPrompt
        XCTAssertTrue(p.contains("Aria"))
        XCTAssertFalse(p.contains("Friday"))
        // Still instructs the structured schema the orchestrator depends on:
        XCTAssertTrue(p.contains("\"type\""))
        XCTAssertTrue(p.contains("\"actions\""))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GeminiClientTests/testSystemPromptIsAriaAndKeepsSchema`
Expected: FAIL — prompt still says "Friday".

- [ ] **Step 3: Replace the prompt**

In `GeminiClient.swift`, replace `static let systemPrompt = """ ... """` with:

```swift
    static let systemPrompt = """
    You are Aria, an AI agent running natively on the user's Mac. You see their \
    screen (provided as an image) and hear their voice. You are confident, warm, \
    and a little charming — a sharp personal assistant who has it handled. You act; \
    you don't lecture.

    Voice & tone:
    - Keep "message" to 1–2 short sentences. It is spoken aloud and shown in a small card.
    - Confident and natural, with the occasional light touch of charm. Never campy, \
    never corporate filler, no emoji.
    - Confirm actions crisply: "On it." / "Done — Spotify's up." / "Say the word."

    ALWAYS respond with a single JSON object, no prose outside it, matching this schema:
    {
      "type": "answer" | "action" | "multi_action" | "clarify",
      "message": "short, natural text to show/speak to the user",
      "confidence": 0.0-1.0,
      "actions": [ { "tool": "tool_name", "input": { "key": "value" } } ],
      "followup": "optional follow-up question, or null"
    }

    Use "answer" for direct responses, "clarify" when you genuinely need more info, \
    and "action"/"multi_action" when the task needs tools.
    """
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter GeminiClientTests`
Expected: PASS (all GeminiClient tests, including the new one).

- [ ] **Step 5: Commit**

```bash
git add Sources/Aria/Core/GeminiClient.swift Tests/AriaTests/GeminiClientTests.swift
git commit -m "feat: Aria confident-and-charming system prompt"
```

---

## Phase 5 — Accent theming

### Task 5.1: Theme + accent persistence (TDD)

**Files:**
- Create: `Sources/Aria/Utilities/Theme.swift`
- Modify: `Sources/Aria/Utilities/AppSettings.swift`
- Test: `Tests/AriaTests/ThemeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Aria

final class ThemeTests: XCTestCase {
    func testPresetIDsResolve() {
        XCTAssertNotNil(Theme.presetColor(id: "blue"))
        XCTAssertNotNil(Theme.presetColor(id: "graphite"))
        XCTAssertNil(Theme.presetColor(id: "nope"))
    }

    func testHexParsing() {
        XCTAssertNotNil(Theme.color(fromHex: "#3B82F6"))
        XCTAssertNotNil(Theme.color(fromHex: "3B82F6"))
        XCTAssertNil(Theme.color(fromHex: "xyz"))
    }

    func testChoiceEncodingRoundTrip() {
        XCTAssertEqual(Theme.decodeChoice(Theme.encode(.system)), .system)
        XCTAssertEqual(Theme.decodeChoice(Theme.encode(.preset("teal"))), .preset("teal"))
        XCTAssertEqual(Theme.decodeChoice(Theme.encode(.custom(hex: "#FF8800"))), .custom(hex: "#FF8800"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ThemeTests`
Expected: FAIL — `Theme` undefined.

- [ ] **Step 3: Implement Theme**

```swift
import SwiftUI
import AppKit

/// Accent-color theming. The only customizable color in Aria; everything else is
/// neutral system material.
enum AccentChoice: Equatable {
    case system
    case preset(String)
    case custom(hex: String)
}

enum Theme {
    /// Curated calm presets (id, display name, color).
    static let presets: [(id: String, name: String, color: Color)] = [
        ("graphite", "Graphite", Color(red: 0.55, green: 0.58, blue: 0.62)),
        ("blue",     "Blue",     Color(red: 0.23, green: 0.51, blue: 0.96)),
        ("teal",     "Teal",     Color(red: 0.10, green: 0.70, blue: 0.67)),
        ("violet",   "Violet",   Color(red: 0.55, green: 0.40, blue: 0.95)),
        ("amber",    "Amber",    Color(red: 0.96, green: 0.70, blue: 0.20)),
        ("rose",     "Rose",     Color(red: 0.95, green: 0.40, blue: 0.55)),
        ("green",    "Green",    Color(red: 0.25, green: 0.78, blue: 0.45)),
    ]

    static func presetColor(id: String) -> Color? {
        presets.first { $0.id == id }?.color
    }

    /// Resolve the live accent color for a choice.
    static func color(for choice: AccentChoice) -> Color {
        switch choice {
        case .system: return Color(nsColor: .controlAccentColor)
        case .preset(let id): return presetColor(id: id) ?? Color(nsColor: .controlAccentColor)
        case .custom(let hex): return color(fromHex: hex) ?? Color(nsColor: .controlAccentColor)
        }
    }

    /// Parse "#RRGGBB" or "RRGGBB" → Color; nil if invalid.
    static func color(fromHex raw: String) -> Color? {
        var hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    // Encode/decode for UserDefaults persistence.
    static func encode(_ choice: AccentChoice) -> String {
        switch choice {
        case .system: return "system"
        case .preset(let id): return "preset:\(id)"
        case .custom(let hex): return "custom:\(hex)"
        }
    }

    static func decodeChoice(_ raw: String) -> AccentChoice {
        if raw == "system" { return .system }
        if raw.hasPrefix("preset:") { return .preset(String(raw.dropFirst(7))) }
        if raw.hasPrefix("custom:") { return .custom(hex: String(raw.dropFirst(7))) }
        return .system
    }
}
```

- [ ] **Step 4: Add accent persistence to AppSettings**

In `AppSettings.swift` add:

```swift
    @Published var accentChoiceRaw: String { didSet { defaults.set(accentChoiceRaw, forKey: K.accentChoice) } }
    var accentChoice: AccentChoice {
        get { Theme.decodeChoice(accentChoiceRaw) }
        set { accentChoiceRaw = Theme.encode(newValue) }
    }
    var accentColor: Color { Theme.color(for: accentChoice) }
```

In `init`: `accentChoiceRaw = defaults.string(forKey: K.accentChoice) ?? "system"`
In `enum K`: `static let accentChoice = "app.accentChoice"`

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ThemeTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Aria/Utilities/Theme.swift Sources/Aria/Utilities/AppSettings.swift Tests/AriaTests/ThemeTests.swift
git commit -m "feat: Theme accent colors + persistence"
```

### Task 5.2: Apply accent to the pill + accent picker in Settings

**Files:**
- Modify: `Sources/Aria/App/AriaController.swift`
- Modify: `Sources/Aria/UI/SettingsView.swift`

- [ ] **Step 1: Push the accent into the view model**

In `AriaController.swift` `setup`, set the initial accent and observe changes:

```swift
    islandViewModel.accent = AppSettings.shared.accentColor
    settingsCancellable = AppSettings.shared.$accentChoiceRaw
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.islandViewModel.accent = AppSettings.shared.accentColor }
```

Add a stored property `private var settingsCancellable: AnyCancellable?` and `import Combine` if not present.

- [ ] **Step 2: Replace the General tab's orb fields with an accent picker**

In `SettingsView.swift`, rewrite `GeneralSettingsTab` (remove the now-defunct orb position/size pickers; the Island is pinned to the notch):

```swift
struct GeneralSettingsTab: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Picker("Accent", selection: Binding(
                get: { settings.accentChoiceRaw },
                set: { settings.accentChoiceRaw = $0 })) {
                Text("Follow system").tag("system")
                ForEach(Theme.presets, id: \.id) { p in
                    Text(p.name).tag("preset:\(p.id)")
                }
                Text("Custom…").tag(customTag)
            }
            if settings.accentChoiceRaw.hasPrefix("custom:") || settings.accentChoiceRaw == customTag {
                ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: false)
            }
            // Live preview chip.
            HStack(spacing: 8) {
                Text("Preview").foregroundStyle(.secondary)
                Capsule().fill(settings.accentColor).frame(width: 60, height: 10)
            }
            Divider()
            HStack {
                Text("Response duration")
                Slider(value: $settings.responseDuration, in: 3...20, step: 1)
                Text("\(Int(settings.responseDuration))s").monospacedDigit()
            }
            Toggle("Privacy mode (disable screen capture)", isOn: $settings.privacyMode)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .padding()
    }

    private let customTag = "custom:#3B82F6"

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { settings.accentColor },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .systemBlue
                let hex = String(format: "#%02X%02X%02X",
                                 Int(ns.redComponent * 255),
                                 Int(ns.greenComponent * 255),
                                 Int(ns.blueComponent * 255))
                settings.accentChoiceRaw = "custom:\(hex)"
            })
    }
}
```

Note: `AppSettings.OrbPosition` / `OrbSize` enums become unused after this; leave them defined (harmless) or delete them in a follow-up cleanup commit.

- [ ] **Step 3: Build, test, manual, commit**

```bash
swift build && swift test
make run   # Settings → General → change Accent (system / presets / custom); confirm the pill's waveform/dot/keyline update live
git add -A
git commit -m "feat: accent picker in Settings, live-applied to the pill"
```

---

## Phase 6 — System integration + repo rename (GATED)

> These steps touch system state and the remote repo. **Confirm with the user before running 6.1 and 6.2** (per the spec's call-outs).

### Task 6.1: Launch agent + old app cleanup

**Files:**
- System: `~/Library/LaunchAgents/com.friday.assistant.plist`, `~/Applications/Friday.app`

- [ ] **Step 1: Build the new app bundle**

```bash
cd ~/Desktop/Friday
make cert      # creates "Aria Self-Signed" so permissions persist
make release   # builds .build/Aria.app, signed
```
Expected: "Built .build/Aria.app".

- [ ] **Step 2: Remove the old Friday launch agent and app (confirm first)**

```bash
launchctl unload ~/Library/LaunchAgents/com.friday.assistant.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.friday.assistant.plist
rm -rf ~/Applications/Friday.app
```

- [ ] **Step 3: Install Aria + grant permissions**

Open `.build/Aria.app` (or `make release` output path), grant Microphone / Speech / Screen Recording when prompted (new bundle id ⇒ fresh prompts). Toggle "Launch at login" in Settings → General to register the new login item.

- [ ] **Step 4: Verify**

Say "Hey Aria, open Spotify" on the installed app; confirm wake, action, voice, and multi-wake all work.

### Task 6.2: Rename the GitHub repo (GATED)

- [ ] **Step 1: Rename via API (confirm first)**

```bash
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill | sed -n 's/^password=//p')
curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/coderarush/Friday -d '{"name":"Aria"}' | grep -E '"full_name"'
unset TOKEN
```
Expected: `"full_name": "coderarush/Aria"`.

- [ ] **Step 2: Update the local remote**

```bash
cd ~/Desktop/Friday
git remote set-url origin https://github.com/coderarush/Aria.git
git remote -v
```

### Task 6.3: Docs

**Files:**
- Modify: `README.md`, `CONTRIBUTING.md`

- [ ] **Step 1: Update doc references**

```bash
cd ~/Desktop/Friday
grep -rl 'Friday' README.md CONTRIBUTING.md | xargs sed -i '' 's/Friday/Aria/g'
```
Then manually fix any "Hey Friday" → "Hey Aria" and screenshots/paths the sed missed.

- [ ] **Step 2: Commit and push**

```bash
git add -A
git commit -m "docs: update README/CONTRIBUTING for Aria; rename complete"
git push origin main
git tag -a v2.0.0 -m "Aria v2.0.0 — Dynamic Island UI, voice, personality, theming"
git push origin v2.0.0
```

---

## Final verification checklist

- [ ] `swift build` — `Build complete!`
- [ ] `swift test` — `0 failures` (NotchGeometry, IslandViewModel, VoiceEngine, Theme, GeminiClient prompt, plus existing suite; OrbShaderTests removed)
- [ ] `make run` — pill at notch; "Hey Aria" wakes; morphs listening→thinking→responding; **voice speaks**; **multiple consecutive wakes work** (v1.0 cascade fix intact)
- [ ] Settings → Voice toggles/changes the voice live
- [ ] Settings → General changes the accent live
- [ ] No `Friday`/`friday` references remain: `grep -ri "friday" Sources Tests Package.swift Resources Makefile` returns nothing (except, if intentionally kept, the `OrbPosition`/`OrbSize` leftovers — delete in cleanup)
