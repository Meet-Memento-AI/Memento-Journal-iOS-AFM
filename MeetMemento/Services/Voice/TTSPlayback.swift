//
//  TTSPlayback.swift
//  MeetMemento
//
//  Spec 031 R2's playback graph: an `AVAudioEngine` + `AVAudioPlayerNode` that
//  schedules rendered buffers and reports when each has finished **playing**.
//
//  Replaces the Pass-1 `NeuralVoicePlayer`, which existed only so the four
//  voices could be auditioned in Settings.
//
//  ⚠️ THE ONE LINE THAT MATTERS: completion is `.dataPlayedBack`, never
//  `.dataConsumed`. `.dataConsumed` fires when the player *takes* the buffer —
//  which, on the conversation path, re-arms the microphone while audio is still
//  sounding, so the app hears itself. That is spec 028 R3's failure class
//  wearing a new disguise, and it is invisible in testing until it isn't.
//

import AVFoundation
import Foundation

@MainActor
final class TTSPlayback {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configuredFormat: AVAudioFormat?

    /// Settings previews own their session; the conversation path does not —
    /// there `VoicePlaybackService` owns `AVAudioSession` explicitly so the
    /// synthesizer never flips a category under `SpeechService`'s feet
    /// (spec 028 R2 keeps the loop strictly half-duplex).
    private let managesAudioSession: Bool

    /// Bumped by `flushAndStop()`. Completion handlers for buffers scheduled
    /// before the bump are ignored — they are still in flight inside CoreAudio
    /// and will fire regardless.
    private var generation: UInt64 = 0

    init(managesAudioSession: Bool) {
        self.managesAudioSession = managesAudioSession
    }

    /// Schedules `buffer` after everything already queued, calling `onPlayed`
    /// once it has finished sounding.
    ///
    /// Buffers queue back-to-back on one player node, so joins are sample-
    /// accurate and gapless (spec 032 R2). Any pacing between sentences is
    /// applied by the caller as a delay on the completion, never as silence
    /// baked into the audio.
    func enqueue(_ buffer: AVAudioPCMBuffer, onPlayed: @escaping () -> Void) throws {
        try configureIfNeeded(format: buffer.format)
        if !engine.isRunning { try engine.start() }

        let scheduled = generation
        player.scheduleBuffer(buffer, at: nil, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Fires on an internal CoreAudio thread.
            Task { @MainActor in
                guard let self, self.generation == scheduled else { return }
                onPlayed()
            }
        }
        if !player.isPlaying { player.play() }
    }

    /// Drops everything sounding and queued.
    func flushAndStop() {
        generation &+= 1
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        // The graph is left attached and connected; the next `enqueue` restarts
        // it. Tearing down and rebuilding per utterance is what makes the first
        // sentence of every turn expensive.
    }

    func pause() {
        if player.isPlaying { player.pause() }
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        player.play()
    }

    private func configureIfNeeded(format: AVAudioFormat) throws {
        // Supertonic always renders 44.1 kHz mono Float32, so this runs once.
        // Guarding on the format rather than a bool means a future format
        // change reconnects instead of silently mis-playing.
        if let configuredFormat, configuredFormat == format { return }

        if managesAudioSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        }

        if configuredFormat != nil {
            engine.disconnectNodeOutput(player)
        } else {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        configuredFormat = format
    }
}
