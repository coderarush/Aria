import Foundation
import Speech
import AVFoundation

typealias TranscriptChunkHandler = @Sendable (_ chunk: String, _ chunkIndex: Int) async -> Void

enum AmbientTranscriptionError: Error, Equatable {
    case permissionDenied
    case recognizerUnavailable
    case audioEngineError(String)
}

/// Shared continuous transcription actor. No wake word. Delivers transcript in chunks
/// via callback. Intended for LectureSession + MeetingSession to share a single
/// recognition pipeline.
actor AmbientTranscriptionEngine {

    enum State: Equatable { case idle, running, paused }
    private(set) var state: State = .idle

    // MARK: Injectable seams (override in tests via configure())

    var requestAuthorization: @Sendable () async -> SFSpeechRecognizerAuthorizationStatus = {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { status in c.resume(returning: status) }
        }
    }
    var recognizerFactory: @Sendable (Locale) -> SFSpeechRecognizer? = { locale in
        SFSpeechRecognizer(locale: locale)
    }
    var now: @Sendable () -> Date = { Date() }

    /// Convenience for tests: mutate injectable seams from outside the actor.
    func configure(
        requestAuthorization: (@Sendable () async -> SFSpeechRecognizerAuthorizationStatus)? = nil,
        recognizerFactory: (@Sendable (Locale) -> SFSpeechRecognizer?)? = nil,
        now: (@Sendable () -> Date)? = nil
    ) {
        if let ra = requestAuthorization { self.requestAuthorization = ra }
        if let rf = recognizerFactory { self.recognizerFactory = rf }
        if let n = now { self.now = n }
    }

    // MARK: Private state

    private var accumulatedText = ""
    private var chunkIndex = 0
    private var lastWordTime: Date = Date()
    private var chunkStartTime: Date = Date()
    private var chunkTask: Task<Void, Never>?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var sessionID = 0  // incremented each start/restart to guard stale callbacks

    // Captured per-session so restart helpers can close over them without re-reading actor state
    private var currentLocale: String = "en-US"
    private var currentChunkInterval: TimeInterval = 45
    private var currentSilenceGap: TimeInterval = 3
    private var currentOnChunk: TranscriptChunkHandler?
    private var currentRecognizer: SFSpeechRecognizer?

    // MARK: Public API

    func start(
        locale: String = "en-US",
        chunkInterval: TimeInterval = 45,
        silenceGap: TimeInterval = 3,
        onChunk: @escaping TranscriptChunkHandler
    ) async throws {
        guard state == .idle else { return }

        // 1. Permission check
        let authStatus = await requestAuthorization()
        guard authStatus == .authorized else {
            throw AmbientTranscriptionError.permissionDenied
        }

        // 2. Recognizer
        guard let recognizer = recognizerFactory(Locale(identifier: locale)) else {
            throw AmbientTranscriptionError.recognizerUnavailable
        }

        // Persist session parameters for restarts
        currentLocale = locale
        currentChunkInterval = chunkInterval
        currentSilenceGap = silenceGap
        currentOnChunk = onChunk
        currentRecognizer = recognizer

        // 3. Audio engine
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat: AVAudioFormat
        do {
            inputFormat = inputNode.outputFormat(forBus: 0)
        }

        // 4. Recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // 5. Install tap — ONLY touches the request (Sendable, thread-safe append)
        // Capture as local weak ref so the closure never touches actor-isolated state
        let weakReq = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buf, _ in
            weakReq.append(buf)
        }

        // 6. Start engine
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
            recognitionRequest = nil
            throw AmbientTranscriptionError.audioEngineError(error.localizedDescription)
        }

        // 7. Start recognition + reset state
        lastWordTime = now()
        chunkStartTime = now()
        accumulatedText = ""
        chunkIndex = 0
        sessionID += 1
        let myID = sessionID

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task {
                await self.handleRecognitionCallback(myID: myID, result: result, error: error,
                                                     chunkInterval: chunkInterval,
                                                     silenceGap: silenceGap, onChunk: onChunk)
            }
        }

        // 8. Chunk delivery loop (0.5 s tick)
        chunkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                await self.checkChunk(interval: chunkInterval, silenceGap: silenceGap, onChunk: onChunk)
            }
        }

        state = .running
    }

    func pause() async {
        guard state == .running else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        state = .paused
    }

    func resume() async {
        guard state == .paused,
              let engine = audioEngine,
              let recognizer = currentRecognizer,
              let onChunk = currentOnChunk else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // New recognition request for the resumed session
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let weakReq = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buf, _ in
            weakReq.append(buf)
        }

        sessionID += 1
        let myID = sessionID
        let interval = currentChunkInterval
        let gap = currentSilenceGap

        recognitionTask?.cancel()
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task {
                await self.handleRecognitionCallback(myID: myID, result: result, error: error,
                                                     chunkInterval: interval,
                                                     silenceGap: gap, onChunk: onChunk)
            }
        }

        // Restart chunk loop if needed
        chunkTask?.cancel()
        chunkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                await self.checkChunk(interval: interval, silenceGap: gap, onChunk: onChunk)
            }
        }

        state = .running
    }

    func stop() async {
        chunkTask?.cancel()
        chunkTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        accumulatedText = ""
        chunkIndex = 0
        sessionID += 1   // invalidate any in-flight callbacks
        currentOnChunk = nil
        currentRecognizer = nil
        state = .idle
    }

    func currentBuffer() async -> String {
        return accumulatedText
    }

    // MARK: Private helpers

    private func handleRecognitionCallback(
        myID: Int,
        result: SFSpeechRecognitionResult?,
        error: Error?,
        chunkInterval: TimeInterval,
        silenceGap: TimeInterval,
        onChunk: @escaping TranscriptChunkHandler
    ) async {
        guard myID == sessionID else { return }  // stale callback from superseded session

        if let result {
            accumulatedText = result.bestTranscription.formattedString
            lastWordTime = now()
        }

        // On error or final result: restart recognition (keep engine running)
        let isFinal = result?.isFinal ?? false
        if error != nil || isFinal {
            await handleSessionEnd(myID: myID, chunkInterval: chunkInterval,
                                   silenceGap: silenceGap, onChunk: onChunk)
        }
    }

    /// Restart recognition without re-starting the audio engine (session-ID guarded).
    private func handleSessionEnd(
        myID: Int,
        chunkInterval: TimeInterval,
        silenceGap: TimeInterval,
        onChunk: @escaping TranscriptChunkHandler
    ) async {
        guard myID == sessionID, state == .running,
              let engine = audioEngine,
              let recognizer = currentRecognizer else { return }

        // Flush remaining text before restarting
        await checkChunk(interval: 0, silenceGap: 0, onChunk: onChunk)

        // Bump session so the old task's lingering callbacks are ignored
        sessionID += 1
        let newID = sessionID

        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // Re-install tap with new request (remove old first)
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let weakReq = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buf, _ in
            weakReq.append(buf)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task {
                await self.handleRecognitionCallback(myID: newID, result: result, error: error,
                                                     chunkInterval: chunkInterval,
                                                     silenceGap: silenceGap, onChunk: onChunk)
            }
        }

        lastWordTime = now()
        chunkStartTime = now()
        accumulatedText = ""
    }

    /// Fires the chunk callback if the time threshold or silence gap has elapsed.
    private func checkChunk(
        interval: TimeInterval,
        silenceGap: TimeInterval,
        onChunk: @escaping TranscriptChunkHandler
    ) async {
        guard !accumulatedText.isEmpty else { return }
        let t = now()
        let elapsedSinceStart = t.timeIntervalSince(chunkStartTime)
        let elapsedSinceSpeech = t.timeIntervalSince(lastWordTime)

        let timeThresholdMet = interval > 0 && elapsedSinceStart >= interval
        let silenceThresholdMet = silenceGap > 0 && elapsedSinceSpeech >= silenceGap
        // When called with 0/0 (flush on restart), always emit if non-empty
        let forceFlush = interval == 0 && silenceGap == 0

        guard timeThresholdMet || silenceThresholdMet || forceFlush else { return }

        let chunk = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        accumulatedText = ""
        chunkStartTime = t

        let idx = chunkIndex
        chunkIndex += 1
        Task { await onChunk(chunk, idx) }
    }
}
