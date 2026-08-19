//
//  NeuralUtteranceEngine.swift
//  MeetMemento
//
//  `UtteranceEngine` over `SupertonicEngine` + `TTSPlayback` (spec 031 R2).
//  This is the path Narration Mode and per-message read-aloud take.
//
//  Two problems this type exists to solve, neither of which the AVSpeech path
//  has:
//
//  1. **Synthesis is asynchronous but speech is ordered.** `speak` is called on
//     the main actor as sentences stream in; rendering each takes real time
//     (~0.25x realtime on device). Kicking off a Task per sentence would let a
//     short later sentence overtake a long earlier one. So synthesis runs as a
//     single serial pump.
//  2. **The first sentence must not wait for the last.** Because a buffer is
//     scheduled the moment it is rendered, and `AVAudioPlayerNode` queues
//     buffers back-to-back, sentence N+1 renders while sentence N is still
//     sounding. Prefetch is a property of the design rather than a feature
//     bolted onto it.
//

import AVFoundation
import Foundation

@MainActor
final class NeuralUtteranceEngine: NSObject, UtteranceEngine {

    weak var engineDelegate: UtteranceEngineDelegate?

    private let playback: TTSPlayback
    /// Spec 030 R5's fallback. Owned rather than injected upward so the decision
    /// to fall back lives in exactly one place and callers cannot observe it.
    private let fallback: SystemUtteranceEngine
    private let styleIDProvider: () -> String

    /// Rendered and scheduled, not yet finished playing — in play order.
    private var outstanding: [UtteranceID] = []
    /// Accepted, not yet rendered — in call order.
    private var pending: [UtteranceRequest] = []
    private var isRendering = false

    /// Bumped by `stopAll()`, so a render that completes after a barge-in is
    /// discarded instead of being scheduled into the next session.
    private var generation: UInt64 = 0

    /// Latched on the first failure. Once the engine has failed there is no
    /// reason to believe the next sentence will fare better, and retrying per
    /// sentence would stutter between two voices mid-reply.
    private var hasFailedOver = false

    init(playback: TTSPlayback,
         fallback: SystemUtteranceEngine,
         styleIDProvider: @escaping () -> String) {
        self.playback = playback
        self.fallback = fallback
        self.styleIDProvider = styleIDProvider
        super.init()
        self.fallback.engineDelegate = self
    }

    // MARK: - UtteranceEngine

    func speak(_ request: UtteranceRequest) {
        guard !hasFailedOver else {
            fallback.speak(request)
            return
        }
        pending.append(request)
        pump()
    }

    func stopAll() {
        generation &+= 1
        pending.removeAll()
        outstanding.removeAll()
        isRendering = false
        playback.flushAndStop()
        fallback.stopAll()
    }

    func pause() {
        playback.pause()
        fallback.pause()
    }

    func resume() {
        playback.resume()
        fallback.resume()
    }

    func warm() {
        // Loading the graphs is the whole cost; there is no silent utterance to
        // speak, because nothing is streamed to an external service.
        Task { try? await SupertonicEngine.shared.prepare() }
    }

    // MARK: - Serial render pump

    private func pump() {
        guard !isRendering, !pending.isEmpty else { return }
        if hasFailedOver {
            // Drain straight to the fallback. Without this, every queued
            // sentence would attempt its own doomed render first.
            pending.forEach { fallback.speak($0) }
            pending.removeAll()
            return
        }
        isRendering = true
        let request = pending.removeFirst()
        let scheduled = generation
        let styleID = styleIDProvider()
        let speed = SpeechRatePreset.nearest(to: request.rate).neuralSpeed

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let buffer = try await SupertonicEngine.shared.synthesize(
                    text: request.text, styleID: styleID, speed: speed)
                guard self.generation == scheduled else { return }
                try self.schedule(buffer, for: request)
            } catch {
                guard self.generation == scheduled else { return }
                self.failOver(request, error: error)
            }
            self.isRendering = false
            self.pump()
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, for request: UtteranceRequest) throws {
        // Register only once the buffer is accepted. Appending first would leave
        // the id outstanding forever if `enqueue` threw, and an utterance that
        // never ends is a session that never drains — the reply just stops.
        let isFirst = outstanding.isEmpty
        try playback.enqueue(buffer) { [weak self] in
            self?.finished(request.id)
        }
        outstanding.append(request.id)

        // The breath between sentences is scheduled as real silence rather than
        // held as a timer before reporting completion. A timer would not work
        // here: the next sentence is often already rendered and queued, so the
        // player would run straight into it and the pacing would vanish.
        if request.postDelay > 0,
           let gap = Self.silence(like: buffer, seconds: request.postDelay) {
            try playback.enqueue(gap, onPlayed: {})
        }

        // `didStart` for the head of the queue only; the rest are announced as
        // their predecessor finishes, which is exact rather than approximate.
        if isFirst { engineDelegate?.utteranceDidStart(request.id) }
    }

    private func finished(_ id: UtteranceID) {
        guard let index = outstanding.firstIndex(of: id) else { return }
        outstanding.remove(at: index)
        engineDelegate?.utteranceDidEnd(id)
        if let next = outstanding.first { engineDelegate?.utteranceDidStart(next) }
    }

    // MARK: - Fallback (spec 030 R5)

    private func failOver(_ request: UtteranceRequest, error: Error) {
        hasFailedOver = true
        // Loud, but NOT fatal — deliberately no `assertionFailure` here.
        // This runs mid-conversation, and trapping would turn a degraded reply
        // into a crash: strictly worse than the silent swap it is meant to warn
        // about. The Settings preview does trap, because that is an explicit
        // developer action with nothing riding on it.
        AppLogger.log("NEURAL SYNTHESIS FAILED — falling back to the system voice "
                      + "for the rest of this session: \(error)", type: .error)
        // Anything already rendered is abandoned: mixing two voices inside one
        // reply is worse than restarting the remainder in one of them.
        fallback.speak(request)
    }

    // MARK: - Silence

    private static func silence(like buffer: AVAudioPCMBuffer,
                                seconds: TimeInterval) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(buffer.format.sampleRate * seconds)
        guard frames > 0,
              let gap = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames)
        else { return nil }
        gap.frameLength = frames  // AVAudioPCMBuffer allocates zeroed
        return gap
    }
}

// MARK: - Forwarding the fallback's events

extension NeuralUtteranceEngine: UtteranceEngineDelegate {
    // Once failed over, the system engine drives the session directly. The
    // service must not be able to tell the difference.
    func utteranceDidStart(_ id: UtteranceID) { engineDelegate?.utteranceDidStart(id) }
    func utteranceDidEnd(_ id: UtteranceID) { engineDelegate?.utteranceDidEnd(id) }
    func utteranceDidPause(_ id: UtteranceID) { engineDelegate?.utteranceDidPause(id) }
    func utteranceDidResume(_ id: UtteranceID) { engineDelegate?.utteranceDidResume(id) }
}
