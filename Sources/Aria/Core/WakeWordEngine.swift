import Foundation
import AVFoundation
import Speech

/// Always-on, on-device wake-word listener built on SFSpeechRecognizer +
/// AVAudioEngine. Listens for "Hey Aria" (and common mishearings). On wake it
/// switches to command-capture mode, accumulates the spoken command, and fires
/// `onCommand` after a short trailing silence.
///
/// Recognition is restarted on a rolling interval so the phrase is never lost to
/// SFSpeechRecognizer's ~1-minute session cap.
@MainActor
final class WakeWordEngine {

    enum Mode { case wake, command }

    // Callbacks (delivered on the main actor).
    var onWake: (() -> Void)?
    var onCommand: ((String) -> Void)?
    /// Fired when the wake phrase was heard but no command followed.
    var onCommandEmpty: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    /// Surfaced setup/recognition failures (shown on the orb).
    var onError: ((String) -> Void)?

    private var restartPending = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var mode: Mode = .wake
    /// Bumped on every (re)start. A recognition task's completion callback only
    /// acts if its id still matches — so deliberately cancelling the previous
    /// task (which fires its callback with a cancellation error) does NOT
    /// trigger another restart. Without this, each restart's cancel scheduled
    /// the next restart: an infinite ~0.4s loop where recognition never lived
    /// long enough to hear the wake word.
    private var sessionID = 0
    private var commandBuffer = ""
    /// Command text finalized from PRIOR recognition sessions in this capture.
    /// SFSpeechRecognizer ends a session on silence; without carrying this
    /// forward, a command spoken AFTER the wake word (not in the same breath)
    /// is lost when the session restarts. Combined with the live session's
    /// transcript to form `commandBuffer`.
    private var committedCommand = ""
    private var silenceTimer: Timer?
    private var rollingTimer: Timer?

    private let wakeVariants = ["hey aria", "hey arya", "hey aria's",
                               "hey, aria", "aria", "hey ariel"]
    private let commandSilence: TimeInterval = 1.4   // trailing silence once speaking
    private let commandLeadGrace: TimeInterval = 6.0 // time to START the command after wake
    private let rollingRestart: TimeInterval = 50

    private(set) var isRunning = false
    /// When true, incoming transcripts are ignored (used while a command is
    /// being processed so a stray "aria" can't interrupt or dismiss the orb).
    var isSuspended = false

    // MARK: Lifecycle

    func start() throws {
        guard !isRunning else { return }
        guard let recognizer else {
            throw NSError(domain: "Aria.Wake", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable for en-US."])
        }
        guard recognizer.isAvailable else {
            throw NSError(domain: "Aria.Wake", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognition is temporarily unavailable. Check your network or Siri/Dictation settings."])
        }
        isRunning = true
        try beginRecognition()
        scheduleRollingRestart()
        Log.wake.info("Wake word engine started (onDevice: \(recognizer.supportsOnDeviceRecognition))")
    }

    func stop() {
        isRunning = false
        rollingTimer?.invalidate()
        silenceTimer?.invalidate()
        teardownRecognition()
        Log.wake.info("Wake word engine stopped")
    }

    // MARK: Recognition session

    private func beginRecognition() throws {
        // Recycle ONLY the speech request + task; keep the AVAudioEngine and its
        // input tap alive across restarts. Tearing the engine down on every
        // silence-restart is what killed wake: one failed audioEngine.start()
        // used to leave no task → no completion → no further restart, silently
        // dead after the first command. Throwing here lets scheduleRestart retry.
        // Supersede the previous session FIRST so its cancellation callback is
        // ignored (see sessionID). Then tear down the old request/task.
        sessionID &+= 1
        let myID = sessionID
        request?.endAudio()
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Only require on-device if the model is actually available; otherwise
        // fall back to server recognition instead of failing silently.
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        self.request = request

        try ensureAudioEngineRunning()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self, myID == self.sessionID else { return }  // ignore superseded sessions
            if let result {
                self.handleTranscript(result.bestTranscription.formattedString)
            }
            if let error {
                // Genuine session end (silence / 1-min cap). Restart to keep
                // listening. Superseded-session cancellations are filtered above,
                // so this can't cascade into a tight loop.
                Log.wake.debug("Recognition ended: \(error.localizedDescription)")
                Log.trace("recognition ended (mode=\(self.mode)): \(error.localizedDescription)")
                self.scheduleRestart()
            }
        }
    }

    /// Install the mic tap and start the audio engine once; reused across all
    /// recognition restarts (the tap appends to whatever `self.request` currently
    /// is). Throws so callers retry instead of leaving wake permanently dead.
    private func ensureAudioEngineRunning() throws {
        guard !audioEngine.isRunning else { return }
        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        // A zero sample rate means there is no usable input device.
        guard format.sampleRate > 0 else {
            throw NSError(domain: "Aria.Wake", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input available. Check your input device."])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.reportLevel(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Restart recognition once, after a short delay, coalescing rapid retries
    /// so a failing recognizer can't spin the CPU. Runs in BOTH modes: in
    /// command mode a session can end mid-command (silence), and we must keep
    /// listening instead of dropping what the user is saying.
    private func scheduleRestart() {
        guard isRunning, !restartPending else { return }
        // Commit the in-progress command so it survives the new session; the
        // fresh session's transcript starts empty and is appended to this.
        if mode == .command { committedCommand = commandBuffer }
        restartPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isRunning else { return }
            self.restartPending = false
            do {
                try self.beginRecognition()
                Log.trace("recognition restarted (mode=\(self.mode))")
            }
            catch {
                // Keep retrying instead of dying — a transient engine-start
                // failure must not permanently kill wake detection.
                Log.wake.error("Restart failed: \(error.localizedDescription) — retrying")
                Log.trace("recognition restart FAILED: \(error.localizedDescription) — retrying")
                self.scheduleRestart()
            }
        }
    }

    private func teardownRecognition() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func scheduleRollingRestart() {
        rollingTimer = Timer.scheduledTimer(withTimeInterval: rollingRestart, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, self.mode == .wake else { return }
                try? self.beginRecognition()
            }
        }
    }

    // MARK: Transcript handling

    private func handleTranscript(_ text: String) {
        guard !isSuspended else { return }
        let lower = text.lowercased()
        switch mode {
        case .wake:
            if wakeVariants.contains(where: { lower.contains($0) }) {
                Log.wake.info("Wake phrase detected")
                enterCommandMode(initialTranscript: lower)
            }
        case .command:
            // The live session's transcript is cumulative within that session;
            // prepend anything committed from earlier (restarted) sessions.
            let sessionText = stripWakePhrase(from: lower, original: text)
            let combined = committedCommand.isEmpty
                ? sessionText
                : (committedCommand + " " + sessionText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            let grew = combined.count > commandBuffer.count
            commandBuffer = combined
            // Once the user is actually speaking the command, use the short
            // trailing-silence window; otherwise keep waiting out the lead grace.
            if grew { resetSilenceTimer(commandSilence) }
        }
    }

    private func enterCommandMode(initialTranscript: String) {
        mode = .command
        committedCommand = ""
        // Keep the SAME recognition session running — its transcription is
        // cumulative, so a command spoken in the same breath as the wake phrase
        // ("Hey Aria, open Spotify") is preserved. stripWakePhrase removes the
        // wake words. Restarting here would discard the command already spoken.
        commandBuffer = stripWakePhrase(from: initialTranscript, original: initialTranscript)
        onWake?()
        // If the command came in the same breath, finish on short silence;
        // otherwise give a longer grace for the user to start speaking it.
        resetSilenceTimer(commandBuffer.isEmpty ? commandLeadGrace : commandSilence)
    }

    private func resetSilenceTimer(_ timeout: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishCommand() }
        }
    }

    private func finishCommand() {
        let command = commandBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = .wake
        commandBuffer = ""
        committedCommand = ""
        Log.trace("finishCommand: '\(command)' → restarting wake session")
        if command.isEmpty {
            onCommandEmpty?()          // let the UI dismiss the idle orb
        } else {
            onCommand?(command)
        }
        // Fresh session so the next wake doesn't see this command's transcript.
        // Retry on failure — swallowing the error here would leave wake dead
        // after a command (the "works once then won't wake again" bug).
        do { try beginRecognition() }
        catch {
            Log.trace("finishCommand beginRecognition failed: \(error.localizedDescription) — retrying")
            scheduleRestart()
        }
    }

    private func stripWakePhrase(from lower: String, original: String) -> String {
        var result = lower
        for variant in wakeVariants.sorted(by: { $0.count > $1.count }) {
            if let range = result.range(of: variant) {
                result.removeSubrange(result.startIndex..<range.upperBound)
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Audio level (for waveform)

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = (sum / Float(frames)).squareRoot()
        let level = min(1, max(0, rms * 12))  // normalize to ~0...1
        Task { @MainActor in self.onAudioLevel?(level) }
    }
}
