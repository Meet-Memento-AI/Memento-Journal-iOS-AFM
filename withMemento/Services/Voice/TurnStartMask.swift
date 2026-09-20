//
//  TurnStartMask.swift
//  MeetMemento
//
//  Spec 032 R3/R4: pre-rendered 200–300ms clip in the selected voice, or
//  skip silently. A missing clip never falls back to another voice.
//  Masked vs unmasked first-audio are both recorded for Gate V (036).
//

import Foundation

enum TurnStartMask {
    static let skipIfFirstChunkFasterThan: Duration = .milliseconds(250)

    static func clipName(for voiceID: String) -> String {
        "turn-start-\(voiceID)"
    }

    static func url(for voiceID: String) -> URL? {
        Bundle.main.url(forResource: clipName(for: voiceID), withExtension: "caf")
            ?? Bundle.main.url(forResource: clipName(for: voiceID), withExtension: "wav")
    }

    /// Lookup is keyed by the same VoiceCatalog id as synthesis.
    static func shouldPlay(voiceID: String, firstChunkReady: Bool, alreadyPlayed: Bool) -> Bool {
        guard !alreadyPlayed else { return false }
        guard !firstChunkReady else { return false }
        return url(for: voiceID) != nil
    }
}

/// Spec 032 R6 / 036: masked and unmasked first-audio live side by side.
final class TTSLatencyProbe: @unchecked Sendable {
    static let shared = TTSLatencyProbe()

    private let lock = NSLock()
    private(set) var lastUnmaskedFirstAudioMs: Double?
    private(set) var lastMaskedFirstAudioMs: Double?
    private var turnStartedAt: ContinuousClock.Instant?
    private var path: ConversationAudioPath?

    func notePath(_ path: ConversationAudioPath) {
        lock.lock()
        self.path = path
        lock.unlock()
    }

    func markTurnStart() {
        lock.lock()
        turnStartedAt = ContinuousClock.now
        lock.unlock()
    }

    func markFirstAudio(masked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let start = turnStartedAt else { return }
        let ms = Double(start.duration(to: .now).components.seconds) * 1000
            + Double(start.duration(to: .now).components.attoseconds) / 1e15
        if masked {
            lastMaskedFirstAudioMs = ms
        } else {
            lastUnmaskedFirstAudioMs = ms
        }
        AppLogger.log("[TTSLatency] firstAudio masked=\(masked) ms=\(Int(ms)) path=\(String(describing: path))")
    }
}
