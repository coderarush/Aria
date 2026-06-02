import Foundation
import AVFoundation
import Speech

/// Always-on, on-device wake-word listener built on SFSpeechRecognizer +
/// AVAudioEngine. Listens for "Hey Friday" (and common mishearings). On wake it
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
    var onAudioLevel: ((Float) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var mode: Mode = .wake
    private var commandBuffer = ""
    private var silenceTimer: Timer?
    private var rollingTimer: Timer?

    private let wakeVariants = ["hey friday", "hey freddy", "hey frieda",
                               "hey friday's", "friday", "a friday"]
    private let commandSilence: TimeInterval = 1.4
    private let rollingRestart: TimeInterval = 50

    private(set) var isRunning = false

    // MARK: Lifecycle

    func start() throws {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            Log.wake.error("Speech recognizer unavailable")
            throw NSError(domain: "Friday.Wake", code: 1)
        }
        isRunning = true
        try beginRecognition()
        scheduleRollingRestart()
        Log.wake.info("Wake word engine started")
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
        teardownRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.reportLevel(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.handleTranscript(text)
            }
            if error != nil {
                // Restart cleanly on transient errors while running.
                if self.isRunning { try? self.beginRecognition() }
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
        let lower = text.lowercased()
        switch mode {
        case .wake:
            if wakeVariants.contains(where: { lower.contains($0) }) {
                Log.wake.info("Wake phrase detected")
                enterCommandMode(initialTranscript: lower)
            }
        case .command:
            commandBuffer = stripWakePhrase(from: lower, original: text)
            resetSilenceTimer()
        }
    }

    private func enterCommandMode(initialTranscript: String) {
        mode = .command
        commandBuffer = stripWakePhrase(from: initialTranscript, original: initialTranscript)
        onWake?()
        // Fresh recognition session so leftover wake audio doesn't pollute the command.
        try? beginRecognition()
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: commandSilence, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishCommand() }
        }
    }

    private func finishCommand() {
        let command = commandBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        mode = .wake
        commandBuffer = ""
        if !command.isEmpty {
            onCommand?(command)
        }
        // Resume plain wake listening.
        try? beginRecognition()
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
