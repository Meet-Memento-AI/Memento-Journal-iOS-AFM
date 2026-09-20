//
//  SystemUtteranceEngine.swift
//  MeetMemento
//
//  `UtteranceEngine` over `AVSpeechSynthesizer` (spec 031 R2). This is the
//  fallback path — spec 030 R5 — and the path unit tests drive.
//
//  Everything AVSpeech-specific that used to live in `VoicePlaybackService`'s
//  `enqueue` is here now: utterance construction, the rate clamp, the inter-
//  utterance breath, voice assignment, and the silent warm-up utterance. The
//  service is left with session bookkeeping, which is all it should ever have
//  had.
//
//  `SpeechSynthesizing` is still injected here, unchanged, so the existing
//  mock in `VoicePlaybackServiceTests` keeps working against the real
//  translation logic rather than against a stub of it.
//

import AVFoundation
import Foundation

@MainActor
final class SystemUtteranceEngine: NSObject, UtteranceEngine {

    weak var engineDelegate: UtteranceEngineDelegate?

    private let synthesizer: SpeechSynthesizing
    /// Resolved lazily by the owner (`VoicePlaybackService` still owns the
    /// AVSpeech voice catalog, because three other screens warm it).
    private let voiceProvider: () -> AVSpeechSynthesisVoice?

    /// Maps AVSpeech's object identity back to our id. AVSpeechUtterance is the
    /// only thing the delegate hands back, so the translation has to live
    /// somewhere; it lives here rather than leaking into the service.
    private var ids: [ObjectIdentifier: UtteranceID] = [:]
    /// The zero-volume warm-up utterance, deliberately absent from `ids` so its
    /// completion is never reported and never counts toward a session.
    private var warmupUtterance: ObjectIdentifier?

    init(synthesizer: SpeechSynthesizing,
         voiceProvider: @escaping () -> AVSpeechSynthesisVoice? = { nil }) {
        self.synthesizer = synthesizer
        self.voiceProvider = voiceProvider
        super.init()
        synthesizer.synthesizerDelegate = self
    }

    // MARK: - UtteranceEngine

    func speak(_ request: UtteranceRequest) {
        let utterance = AVSpeechUtterance(string: request.text)
        if let voice = voiceProvider() { utterance.voice = voice }
        utterance.rate = min(max(request.rate, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.postUtteranceDelay = request.postDelay
        ids[ObjectIdentifier(utterance)] = request.id
        synthesizer.speak(utterance)
    }

    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
        // Deliberately not cleared: the didCancel callbacks are still in flight,
        // and dropping the mapping now would strand them. The service ignores
        // ids that are no longer in its active set, which is the same guard that
        // makes a barge-in safe.
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    /// Speaks a zero-volume space so the synthesizer engine is live before the
    /// first real sentence.
    func warm() {
        let utterance = AVSpeechUtterance(string: " ")
        utterance.volume = 0
        utterance.rate = AVSpeechUtteranceMaximumSpeechRate
        if let voice = voiceProvider() { utterance.voice = voice }
        warmupUtterance = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    // MARK: - Translation

    /// Resolves an AVSpeech utterance to our id, dropping the warm-up utterance
    /// and anything already reported.
    private func identify(_ utterance: AVSpeechUtterance) -> UtteranceID? {
        let key = ObjectIdentifier(utterance)
        guard warmupUtterance != key else { return nil }
        return ids[key]
    }

    fileprivate func ended(_ utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        if warmupUtterance == key {
            warmupUtterance = nil
            return
        }
        guard let id = ids.removeValue(forKey: key) else { return }
        engineDelegate?.utteranceDidEnd(id)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemUtteranceEngine: AVSpeechSynthesizerDelegate {
    // Callbacks may arrive off-main; hop before touching any state. The service
    // guards staleness by generation, so nothing here needs to.

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let id = self.identify(utterance) else { return }
            self.engineDelegate?.utteranceDidStart(id)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.ended(utterance) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.ended(utterance) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let id = self.identify(utterance) else { return }
            self.engineDelegate?.utteranceDidPause(id)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let id = self.identify(utterance) else { return }
            self.engineDelegate?.utteranceDidResume(id)
        }
    }
}
