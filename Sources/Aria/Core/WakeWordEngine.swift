import Foundation
import AVFoundation
import Speech

/// Always-on wake-word listener built on SFSpeechRecognizer. As of v5.1 it no longer
/// owns the mic — `AudioBus` owns one audio engine, runs echo cancellation, and feeds
/// the CLEANED mic frames here via `acceptCleanedFrame`. Because the recognizer never
/// hears Aria's own voice, talk-over barge-in works and self-trigger is gone; and a
/// guarded restart + watchdog (RecognitionLifecycle) keeps it from ever going deaf.
///
/// Listens for "Hey Aria" (and common mishearings); on wake it captures the command
/// and fires `onCommand` after a short trailing silence.
@MainActor
final class WakeWordEngine {

    enum Mode { case wake, command }

    // Callbacks (delivered on the main actor).
    var onWake: (() -> Void)?
    var onCommand: ((String) -> Void)?
    var onCommandEmpty: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?
    /// Experimental speaker gate: when set, a detected wake only proceeds if this
    /// returns true for the utterance's voiceprint. nil (default) = no gating.
    var verifyWake: (([Float]) -> Bool)? { didSet { gateActive = (verifyWake != nil) } }
    private nonisolated(unsafe) var gateActive = false
    private var recentVoiceprints: [[Float]] = []

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartPending = false

    // Audio-thread-safe handle to the current request: AudioBus calls
    // `acceptCleanedFrame` from its audio thread, so the append must not touch
    // main-actor state. The request pointer is swapped under a lock.
    private let feedLock = NSLock()
    private nonisolated(unsafe) var feedRequest: SFSpeechAudioBufferRecognitionRequest?
    private nonisolated static let feedFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                              sampleRate: AudioBus.aecRate,
                                                              channels: 1, interleaved: true)!

    private var lifecycle = RecognitionLifecycle()
    private var mode: Mode = .wake
    private var commandBuffer = ""
    private var committedCommand = ""
    private var silenceTimer: Timer?
    private var rollingTimer: Timer?
    private var watchdogTimer: Timer?

    private let wakeVariants = ["hey aria", "hey arya", "hey aria's",
                               "hey, aria", "aria", "hey ariel"]
    private let commandSilence: TimeInterval = 1.4
    private let commandLeadGrace: TimeInterval = 6.0
    private let rollingRestart: TimeInterval = 50
    private let watchdogTimeout: TimeInterval = 8

    private(set) var isRunning = false
    var isSuspended = false
    var conversationActive = false
    var isInWakeMode: Bool { mode == .wake }

    // MARK: Lifecycle

    /// Start recognition. The mic is owned by `AudioBus`; this only sets up the
    /// recognizer + keep-alive timers and relies on `acceptCleanedFrame` for audio.
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
        beginRecognition()
        lifecycle.sawAudio(at: Date.timeIntervalSinceReferenceDate)   // arm the watchdog
        scheduleRollingRestart()
        scheduleWatchdog()
        Log.wake.info("Wake word engine started (onDevice: \(recognizer.supportsOnDeviceRecognition))")
    }

    func stop() {
        isRunning = false
        rollingTimer?.invalidate()
        watchdogTimer?.invalidate()
        silenceTimer?.invalidate()
        teardownRecognition()
        Log.wake.info("Wake word engine stopped")
    }

    /// Called from AudioBus's audio thread with cleaned 16 kHz mono Int16 frames.
    nonisolated func acceptCleanedFrame(_ samples: [Int16]) {
        guard let buf = WakeWordEngine.buffer(from: samples) else { return }
        feedLock.lock(); let req = feedRequest; feedLock.unlock()
        req?.append(buf)
        let rms = WakeWordEngine.rms(samples)
        // Only fingerprint voiced frames while the speaker gate is active (off by default).
        let voiceprint: [Float]? = (gateActive && rms > 0.05) ? VoiceFeatures.extract(samples) : nil
        Task { @MainActor in self.noteAudio(level: rms, voiceprint: voiceprint) }
    }

    @MainActor private func noteAudio(level: Float, voiceprint: [Float]? = nil) {
        lifecycle.sawAudio(at: Date.timeIntervalSinceReferenceDate)
        onAudioLevel?(min(1, max(0, level)))
        if let vp = voiceprint {
            recentVoiceprints.append(vp)
            if recentVoiceprints.count > 30 { recentVoiceprints.removeFirst(recentVoiceprints.count - 30) }
        }
    }

    // MARK: Recognition session

    private func beginRecognition() {
        let myID = lifecycle.begin()           // supersede any prior session
        request?.endAudio()
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        self.request = request
        feedLock.lock(); feedRequest = request; feedLock.unlock()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.lifecycle.shouldRestart(forSession: myID) else { return }  // ignore superseded
                if let result { self.handleTranscript(result.bestTranscription.formattedString) }
                if let error {
                    Log.trace("recognition ended (mode=\(self.mode)): \(error.localizedDescription)")
                    self.scheduleRestart()
                }
            }
        }
    }

    private func scheduleRestart() {
        guard isRunning, !restartPending else { return }
        if mode == .command { committedCommand = commandBuffer }
        restartPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isRunning else { return }
            self.restartPending = false
            self.beginRecognition()
            Log.trace("recognition restarted (mode=\(self.mode))")
        }
    }

    private func teardownRecognition() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        feedLock.lock(); feedRequest = nil; feedLock.unlock()
    }

    private func scheduleRollingRestart() {
        rollingTimer = Timer.scheduledTimer(withTimeInterval: rollingRestart, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, self.mode == .wake else { return }
                self.beginRecognition()
            }
        }
    }

    /// Never-deaf watchdog: if no cleaned audio has arrived for `watchdogTimeout`,
    /// the recognizer/feed is silently dead — rebuild it.
    private func scheduleWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                if self.lifecycle.watchdogExpired(now: Date.timeIntervalSinceReferenceDate, timeout: self.watchdogTimeout) {
                    Log.trace("watchdog: no audio for \(self.watchdogTimeout)s — rebuilding recognition")
                    self.lifecycle.sawAudio(at: Date.timeIntervalSinceReferenceDate)
                    self.beginRecognition()
                }
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
            let sessionText = stripWakePhrase(from: lower, original: text)
            let combined = committedCommand.isEmpty
                ? sessionText
                : (committedCommand + " " + sessionText).trimmingCharacters(in: .whitespacesAndNewlines)
            let grew = combined.count > commandBuffer.count
            commandBuffer = combined
            if grew { resetSilenceTimer(commandSilence) }
        }
    }

    private func enterCommandMode(initialTranscript: String) {
        // Experimental speaker gate: reject the wake if the voice doesn't match the
        // enrolled owner. Inert (always proceeds) unless a gate is wired + enrolled.
        if let verify = verifyWake, !recentVoiceprints.isEmpty {
            let print = SpeakerVerifier.averaged(recentVoiceprints)
            recentVoiceprints = []
            if !verify(print) {
                Log.trace("wake rejected — voice didn't match the enrolled owner")
                return
            }
        } else {
            recentVoiceprints = []
        }
        mode = .command
        committedCommand = ""
        commandBuffer = stripWakePhrase(from: initialTranscript, original: initialTranscript)
        onWake?()
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
        Log.trace("finishCommand: '\(command)' → conversationActive=\(conversationActive)")
        if command.isEmpty { onCommandEmpty?() } else { onCommand?(command) }
        mode = (conversationActive && !command.isEmpty) ? .command : .wake
        commandBuffer = ""
        committedCommand = ""
        beginRecognition()
    }

    /// Programmatic wake (push-to-talk hotkey / menu summon): enter command
    /// capture as if the wake phrase was just heard. Skips the speaker gate —
    /// a physical keypress IS the user. No-op while suspended (Aria speaking)
    /// or already capturing.
    func summon() {
        guard !isSuspended, mode == .wake else { return }
        Log.trace("summon — push-to-talk wake")
        mode = .command
        committedCommand = ""
        commandBuffer = ""
        recentVoiceprints = []
        onWake?()
        resetSilenceTimer(commandLeadGrace)
    }

    /// Leave conversation mode and go back to wake-word listening.
    func endConversation() {
        conversationActive = false
        isSuspended = false
        mode = .wake
        commandBuffer = ""; committedCommand = ""
        silenceTimer?.invalidate()
        beginRecognition()
    }

    /// Start a CLEAN recognition session for the next turn.
    func freshTurn() {
        commandBuffer = ""; committedCommand = ""
        silenceTimer?.invalidate()
        mode = conversationActive ? .command : .wake
        beginRecognition()
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

    // MARK: Audio helpers (nonisolated — run on the audio thread)

    private nonisolated static func buffer(from samples: [Int16]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: feedFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let dst = buf.int16ChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }
        return buf
    }

    private nonisolated static func rms(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return Float(rms / 32768.0 * 12)   // normalize toward ~0…1 (matches old scaling)
    }
}
