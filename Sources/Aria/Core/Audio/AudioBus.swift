import Foundation
import AVFoundation

/// The single owner of audio I/O. One AVAudioEngine taps the mic and plays Aria's
/// TTS through a player node, so we hold her exact audio as the AEC far-end. It
/// resamples mic + TTS to 16 kHz mono, runs the EchoCanceller, and publishes the
/// cleaned near-end as Int16 frames via `onCleanedFrame`. Fully local + free.
final class AudioBus {
    static let aecRate: Double = 16000
    static let frameSize = 160                 // 10 ms @ 16 kHz

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let aec = EchoCanceller(frameSize: frameSize, filterTaps: frameSize * 16, sampleRate: Int(aecRate))
    private let aecFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: aecRate, channels: 1, interleaved: true)!

    private var micRing = FrameRing(frameSize: frameSize)   // audio thread only
    private var farRing = FrameRing(frameSize: frameSize)   // pushed (main) + popped (audio) → farLock
    private let farLock = NSLock()
    private var micConverter: AVAudioConverter?

    /// Emits cleaned 16 kHz mono Int16 frames (echo removed), on the audio thread.
    var onCleanedFrame: (([Int16]) -> Void)?
    /// Fires true when Aria starts speaking, false when she stops (drives barge-in).
    var onPlayStateChange: ((Bool) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        micConverter = AVAudioConverter(from: inFormat, to: aecFormat)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in
            self?.handleMic(buf)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func handleMic(_ buffer: AVAudioPCMBuffer) {
        guard let conv = micConverter,
              let i16 = AudioBus.convert(buffer, with: conv, to: aecFormat) else { return }
        micRing.push(i16)
        drain()
    }

    /// Echo-tail window after playback during which the filter keeps running.
    static let aecTailSeconds: TimeInterval = 2.0
    /// Last moment far-end audio was queued or playing (audio thread; farLock).
    private var lastPlaybackActivity: TimeInterval = 0

    /// True when the echo canceller can be skipped entirely: nothing queued on
    /// the far end and playback ended past the echo tail. At idle this is the
    /// app's main CPU cost (full Speex MDF math per mic frame for a guaranteed
    /// near-passthrough) — measured ~9% of a core; bypassing drops idle CPU to
    /// the platform audio/recognition floor. During and shortly after speech
    /// the filter always runs, so talk-over barge-in is unaffected.
    static func shouldBypassAEC(farQueued: Bool, now: TimeInterval,
                                lastPlaybackActivity: TimeInterval) -> Bool {
        !farQueued && (now - lastPlaybackActivity) > aecTailSeconds
    }

    /// Pair mic + far frames and run AEC. With no far audio queued (Aria silent),
    /// the far-end is zeros and the AEC is a near-passthrough.
    private func drain() {
        while let near = micRing.pop() {
            farLock.lock()
            let far = farRing.pop()
            if far != nil { lastPlaybackActivity = Date.timeIntervalSinceReferenceDate }
            let lastActivity = lastPlaybackActivity
            farLock.unlock()
            let cleaned: [Int16]
            if far == nil, AudioBus.shouldBypassAEC(farQueued: false,
                                                    now: Date.timeIntervalSinceReferenceDate,
                                                    lastPlaybackActivity: lastActivity) {
                cleaned = near
            } else {
                cleaned = aec.process(near: near,
                                      far: far ?? [Int16](repeating: 0, count: AudioBus.frameSize))
            }
            onCleanedFrame?(cleaned)
        }
    }

    /// Play Aria's TTS (16-bit mono PCM at `pcmRate`) AND register it as the AEC
    /// far-end so her voice is cancelled out of the mic.
    ///
    /// The buffer is CONVERTED to the player node's connected format before
    /// scheduling. Scheduling a mismatched buffer raises an ObjC exception
    /// inside AVAudioPlayerNode ("_outputFormat.channelCount ==
    /// buffer.format.channelCount") that Swift cannot catch — on macOS 26.3.1
    /// it killed the capture pipeline on every wake chime and corrupted
    /// concurrency state badly enough to crash later SwiftUI taps.
    func playReference(pcm: Data, pcmRate: Double, onDone: @escaping () -> Void) {
        if let i16 = AudioBus.resampleInt16(pcm: pcm, fromRate: pcmRate, toFormat: aecFormat) {
            farLock.lock(); farRing.push(i16); farLock.unlock()
        }
        let nodeFormat = player.outputFormat(forBus: 0)
        guard let buf = AudioBus.playableBuffer(pcm: pcm, pcmRate: pcmRate, nodeFormat: nodeFormat) else {
            Log.trace("audio: could not prepare playback buffer (\(pcm.count) bytes @ \(pcmRate)Hz)")
            onDone(); return
        }
        onPlayStateChange?(true)
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buf, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.onPlayStateChange?(false)
                onDone()
            }
        }
    }

    /// Mono Int16 PCM → a buffer in exactly `nodeFormat` (sample rate, channel
    /// count, common format). Pass-through when the formats already match.
    static func playableBuffer(pcm: Data, pcmRate: Double, nodeFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !pcm.isEmpty,
              let srcFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: pcmRate,
                                            channels: 1, interleaved: true),
              let src = pcmBuffer(from: pcm, format: srcFormat) else { return nil }
        if srcFormat.commonFormat == nodeFormat.commonFormat,
           srcFormat.sampleRate == nodeFormat.sampleRate,
           srcFormat.channelCount == nodeFormat.channelCount {
            return src
        }
        guard let conv = AVAudioConverter(from: srcFormat, to: nodeFormat) else { return nil }
        let ratio = nodeFormat.sampleRate / srcFormat.sampleRate
        let cap = AVAudioFrameCount(Double(src.frameLength) * ratio + 32)
        guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: nodeFormat, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return src
        }
        guard err == nil, out.frameLength > 0 else { return nil }
        return out
    }

    func stopPlayback() {
        player.stop()
        farLock.lock(); farRing = FrameRing(frameSize: AudioBus.frameSize); farLock.unlock()   // drop pending reference
        onPlayStateChange?(false)
    }

    // MARK: conversion helpers (thin AVAudioConverter wrappers)

    private static func convert(_ buffer: AVAudioPCMBuffer, with conv: AVAudioConverter, to format: AVAudioFormat) -> [Int16]? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if err != nil { return nil }
        guard let ch = out.int16ChannelData, out.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    private static func resampleInt16(pcm: Data, fromRate: Double, toFormat: AVAudioFormat) -> [Int16]? {
        guard let src = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: fromRate, channels: 1, interleaved: true),
              let buf = pcmBuffer(from: pcm, format: src),
              let conv = AVAudioConverter(from: src, to: toFormat) else { return nil }
        return convert(buf, with: conv, to: toFormat)
    }

    private static func pcmBuffer(from pcm: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(pcm.count / 2)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        pcm.withUnsafeBytes { raw in
            if let base = buf.int16ChannelData?[0], let src = raw.bindMemory(to: Int16.self).baseAddress {
                base.update(from: src, count: Int(frames))
            }
        }
        return buf
    }
}
