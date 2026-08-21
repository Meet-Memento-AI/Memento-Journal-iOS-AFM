//
//  ConversationAudioController.swift
//  MeetMemento
//
//  Spec 034: two named audio paths. Conversation uses .playAndRecord +
//  voice processing; read-back stays half-duplex playback. Tap-interrupt
//  always works; acoustic barge-in rides SpeechDetector when the
//  conversation path is live.
//

import AVFoundation
import Foundation

enum ConversationAudioPath: Equatable, Sendable {
    case conversation
    case readBack
}

@MainActor
final class ConversationAudioController: ObservableObject {
    static let shared = ConversationAudioController()

    @Published private(set) var activePath: ConversationAudioPath?
    @Published private(set) var bargeInArmed = false
    /// True once SpeechDetector reports speech while TTS is playing on the
    /// conversation path. Read-back never arms this.
    @Published private(set) var acousticBargeIn = false

    private init() {}

    func activate(_ path: ConversationAudioPath) throws {
        let session = AVAudioSession.sharedInstance()
        switch path {
        case .conversation:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .defaultToSpeaker, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            bargeInArmed = true
        case .readBack:
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            bargeInArmed = false
        }
        try session.setActive(true)
        activePath = path
        acousticBargeIn = false
        TTSLatencyProbe.shared.notePath(path)
    }

    func deactivate() {
        bargeInArmed = false
        acousticBargeIn = false
        activePath = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// SpeechDetector / level-based VAD. Ignored on the read-back path.
    func handleVoiceActivity(_ present: Bool) {
        guard bargeInArmed, activePath == .conversation, present else { return }
        guard VoicePlaybackService.shared.speakingMessageID != nil else { return }
        acousticBargeIn = true
        VoicePlaybackService.shared.stop()
    }

    /// Tap-interrupt is always available, both paths.
    func tapInterrupt() {
        VoicePlaybackService.shared.stop()
        acousticBargeIn = false
    }
}
