//
//  VoicePlaybackService.swift
//  MeetMemento
//
//  Tap-to-speak playback of completed AI chat messages via AVSpeechSynthesizer
//  (spec 018 R7, chat amendment). One message speaks at a time. The public API
//  is a thin composition over stream-ready primitives (beginUtteranceSession /
//  enqueue / finishEnqueueing) so the future streaming sentence-chunker slots
//  in without reworking this file.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit

// MARK: - Synthesizer seam

/// Protocol seam so unit tests can drive the delegate state machine without
/// real audio (simulator TTS is unreliable and CI is headless).
protocol SpeechSynthesizing: AnyObject {
    var synthesizerDelegate: AVSpeechSynthesizerDelegate? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
    @discardableResult func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool
    @discardableResult func continueSpeaking() -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {
    var synthesizerDelegate: AVSpeechSynthesizerDelegate? {
        get { delegate }
        set { delegate = newValue }
    }
}

// MARK: - Service

@MainActor
final class VoicePlaybackService: NSObject, ObservableObject {
    static let shared = VoicePlaybackService()

    // MARK: Published state

    /// The chat message currently being spoken (or prepared). nil = idle.
    /// UI derives everything from this: `speakingMessageID == message.id`.
    @Published private(set) var speakingMessageID: UUID?
    @Published private(set) var isSpeaking = false
    /// True while playback is paused mid-message (in-app tap, interruption,
    /// or headphone unplug). The session stays alive; Resume continues from
    /// the paused word.
    @Published private(set) var isPaused = false
    @Published var errorMessage: String?

    // MARK: Internals

    private let synthesizer: SpeechSynthesizing
    /// When false (unit tests), never touches AVAudioSession.
    private let managesAudioSession: Bool
    /// Injected so tests can simulate an active dictation without SpeechService.
    private let isRecordingProvider: () -> Bool
    /// Injected so tests can pin the speaking rate without PreferencesService.
    private let rateProvider: () -> Float

    /// Identities of this session's utterances still in the synthesizer. A set
    /// keyed by identity, not a bare count: when a new session starts while
    /// another speaks, the old utterances' didCancel callbacks arrive *after*
    /// the new session enqueued — a count would decrement the new session's
    /// bookkeeping and end it prematurely.
    private var activeUtteranceIDs = Set<ObjectIdentifier>()
    /// Set by `finishEnqueueing()`: when the queue drains after this, the
    /// session ends. Without it, `didFinish` of the last *currently queued*
    /// utterance would prematurely end a streaming session.
    private var inputComplete = false
    /// Bumped on every begin/stop so a late delegate callback from a cancelled
    /// session can't revive state (SpeechService's proven pattern).
    private var sessionGeneration: UInt64 = 0

    private var cancellables = Set<AnyCancellable>()

    /// Resolved voice, cached until the preference changes or the app returns
    /// from the foreground with new voices installed. The user's explicit
    /// choice wins; a since-deleted voice (or no choice) falls back to
    /// `bestVoice()`. Personal Voice deliberately not offered (spec 018 R8 is
    /// verify-gated).
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var voiceCacheValid = false

    private var voice: AVSpeechSynthesisVoice? {
        if !voiceCacheValid {
            if let identifier = PreferencesService.shared.selectedVoiceIdentifier,
               let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
                cachedVoice = chosen
            } else {
                cachedVoice = Self.bestVoice()
            }
            voiceCacheValid = true
        }
        return cachedVoice
    }

    /// Drops the resolved voice so the next utterance re-resolves — called when
    /// the preference changes and when a newly downloaded voice may exist.
    func invalidateVoiceCache() {
        voiceCacheValid = false
    }

    // MARK: Init

    private convenience override init() {
        let synthesizer = AVSpeechSynthesizer()
        // The service owns AVAudioSession lifecycle explicitly instead of the
        // synthesizer flipping a private session under SpeechService's feet.
        synthesizer.usesApplicationAudioSession = true
        self.init(
            synthesizer: synthesizer,
            managesAudioSession: true,
            isRecordingProvider: {
                SpeechService.shared.isRecording || SpeechService.shared.isProcessing
            },
            rateProvider: { PreferencesService.shared.speechRate }
        )

        // A changed voice choice takes effect on the next utterance.
        PreferencesService.shared.$selectedVoiceIdentifier
            .dropFirst()
            .sink { [weak self] _ in self?.invalidateVoiceCache() }
            .store(in: &cancellables)

        // TTS yields to STT: tapping any mic (chat, journal, settings) stops
        // speech before SpeechService reconfigures the shared session to
        // `.record`. SpeechService itself stays untouched and STT-only.
        SpeechService.shared.$isRecording
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.stop() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        // Phone call / Siri / another app's audio focus: stop, no resume in
        // step 1 — a stale half-read message is worse than pressing play again.
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        // Headphones unplugged: pause, don't blast the room.
        center.addObserver(self, selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
        // Note: no didEnterBackground observer — the `audio` background mode
        // (REQ-VOX-005, chat amendment) keeps an in-progress read alive when
        // the app backgrounds or the device locks.

        registerRemoteCommands()
    }

    /// Test seam.
    init(
        synthesizer: SpeechSynthesizing,
        managesAudioSession: Bool,
        isRecordingProvider: @escaping () -> Bool = { false },
        rateProvider: @escaping () -> Float = { SpeechRatePreset.brisk.rawValue }
    ) {
        self.synthesizer = synthesizer
        self.managesAudioSession = managesAudioSession
        self.isRecordingProvider = isRecordingProvider
        self.rateProvider = rateProvider
        super.init()
        synthesizer.synthesizerDelegate = self
    }

    // MARK: - Public API (step 1)

    /// Tap handler. Same message → pause, or resume if paused (user decision:
    /// the in-app button never hard-stops; playback ends at queue drain or
    /// implicitly via dictation/regenerate/another message/lock-screen Stop).
    /// Different message → stop current and speak this one. No-ops during
    /// dictation — the in-progress recording is the user's data; never steal
    /// its session.
    func toggleSpeech(messageID: UUID, heading1: String?, heading2: String?, body: String) {
        if speakingMessageID == messageID {
            isPaused ? continueSpeaking() : pauseSpeaking()
            return
        }
        guard !isRecordingProvider() else { return }

        let text = SpeechTextSanitizer.speakableText(
            heading1: heading1, heading2: heading2, body: body
        )
        guard !text.isEmpty else { return }

        beginUtteranceSession(for: messageID, title: heading1)
        enqueue(sentence: text)
        finishEnqueueing()
    }

    /// Stops playback immediately and releases the audio session. State clears
    /// now — UI flips instantly, hardware tears down off-main (SpeechService's
    /// philosophy).
    func stop() {
        guard speakingMessageID != nil else { return }
        sessionGeneration &+= 1
        synthesizer.stopSpeaking(at: .immediate)
        clearSession()
    }

    /// Targeted stop for regenerate/delete paths: only acts if this message is
    /// the one speaking.
    func stopIfSpeaking(messageID: UUID) {
        guard speakingMessageID == messageID else { return }
        stop()
    }

    /// Pauses at the current word. State flips eagerly (snappy UI); the
    /// delegate's didPause confirms.
    func pauseSpeaking() {
        guard speakingMessageID != nil, !isPaused else { return }
        isPaused = true
        synthesizer.pauseSpeaking(at: .word)
        updateNowPlayingRate(0.0)
    }

    /// Resumes a paused session from the paused word.
    func continueSpeaking() {
        guard speakingMessageID != nil, isPaused else { return }
        isPaused = false
        synthesizer.continueSpeaking()
        updateNowPlayingRate(1.0)
    }

    // MARK: - Stream-ready primitives (the future chunker's API)

    /// Opens a playback session attributed to `messageID`: stops any current
    /// speech, activates the audio session, sets state, and publishes
    /// lock-screen metadata. `title` names the read on the lock screen
    /// (message heading, or the app-generic fallback). Utterances may then be
    /// enqueued incrementally.
    func beginUtteranceSession(for messageID: UUID, title: String? = nil) {
        sessionGeneration &+= 1
        if speakingMessageID != nil {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingMessageID = messageID
        isSpeaking = false
        isPaused = false
        errorMessage = nil
        activeUtteranceIDs.removeAll()
        inputComplete = false
        activateAudioSessionIfNeeded()
        publishNowPlaying(title: title)
    }

    /// Enqueue one sentence/paragraph as its own utterance. Sanitizes
    /// internally — the single choke point, so every caller (tap today, the
    /// chunker later) produces clean speech. AVSpeechSynthesizer queues
    /// utterances FIFO natively.
    func enqueue(sentence: String) {
        guard speakingMessageID != nil else { return }
        let text = SpeechTextSanitizer.sanitize(sentence)
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        if let voice { utterance.voice = voice }
        // User preference (SpeechRatePreset); default Brisk 0.53 — system 0.5
        // reads slightly slow for conversational AI.
        utterance.rate = min(max(rateProvider(), AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        // A breath between parts (heading → body, sentence → sentence).
        utterance.postUtteranceDelay = 0.25
        activeUtteranceIDs.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    /// Marks input complete: once the synthesizer queue drains past this,
    /// the session ends and state clears.
    func finishEnqueueing() {
        guard speakingMessageID != nil else { return }
        inputComplete = true
        endSessionIfDrained()
    }

    // MARK: - Settings preview

    /// Session ID for voice/rate previews from Settings — a fixed UUID so a
    /// preview never matches any chat message's `speakingMessageID`.
    static let previewSessionID = UUID(uuidString: "D19A7E55-0000-4000-8000-5E77E5501D01")!

    /// Speaks a one-line sample with the current voice/rate preferences.
    /// Used by VoiceSettingsView so a picked voice is audible immediately.
    func speakPreview() {
        guard !isRecordingProvider() else { return }
        beginUtteranceSession(for: Self.previewSessionID, title: "Voice preview")
        enqueue(sentence: "Hi, I'm Memento. This is how I'll sound.")
        finishEnqueueing()
    }

    // MARK: - Session bookkeeping

    private func clearSession() {
        speakingMessageID = nil
        isSpeaking = false
        isPaused = false
        activeUtteranceIDs.removeAll()
        inputComplete = false
        deactivateAudioSessionIfNeeded()
        clearNowPlaying()
    }

    // MARK: - Lock screen (REQ-VOX-005, chat amendment)

    // All gated on `managesAudioSession` so unit tests never touch
    // MPNowPlayingInfoCenter. No duration/elapsed: AVSpeechSynthesizer has no
    // natural duration, and an estimated scrubber would lie — title + play
    // state is honest and sufficient.

    private func publishNowPlaying(title: String?) {
        guard managesAudioSession else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: (title?.isEmpty == false ? title! : "Memento reply"),
            MPMediaItemPropertyArtist: "Memento",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    private func updateNowPlayingRate(_ rate: Double) {
        guard managesAudioSession else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        guard managesAudioSession else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Lock-screen / Control Center transport. Registered once (singleton's
    /// private init). Stop IS offered here even though the in-app button is
    /// pause/resume-only — with the screen off, "make it stop talking"
    /// deserves a one-tap answer.
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.speakingMessageID != nil else { return .commandFailed }
            Task { @MainActor in self.continueSpeaking() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.speakingMessageID != nil else { return .commandFailed }
            Task { @MainActor in self.pauseSpeaking() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.speakingMessageID != nil else { return .commandFailed }
            Task { @MainActor in
                self.isPaused ? self.continueSpeaking() : self.pauseSpeaking()
            }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            guard let self, self.speakingMessageID != nil else { return .commandFailed }
            Task { @MainActor in self.stop() }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func endSessionIfDrained() {
        if inputComplete && activeUtteranceIDs.isEmpty {
            clearSession()
        }
    }

    // MARK: - System events

    // The @objc handlers are thin notification parsers; the internal methods
    // hold the behavior so unit tests can drive them without posting real
    // AVAudioSession notifications.

    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            Task { @MainActor in self.interruptionBegan() }
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                .contains(.shouldResume)
            Task { @MainActor in self.interruptionEnded(shouldResume: shouldResume) }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        // Headphones unplugged: pause, don't blast the room. Resumable from
        // the button or the lock screen.
        Task { @MainActor in self.pauseSpeaking() }
    }

    /// Phone call / Siri / another app took the session: pause, keep position.
    func interruptionBegan() {
        pauseSpeaking()
    }

    /// The interrupter finished. Resume only when the system says the app
    /// should (`.shouldResume`); otherwise stay paused with the visible
    /// Resume affordance.
    func interruptionEnded(shouldResume: Bool) {
        guard shouldResume else { return }
        continueSpeaking()
    }

    // MARK: - Audio session (off-main, watchdog-safe)

    private func activateAudioSessionIfNeeded() {
        guard managesAudioSession else { return }
        let generation = sessionGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Self.performPlaybackSessionSetup()
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    self.errorMessage = "Audio playback unavailable: \(error.localizedDescription)"
                    self.synthesizer.stopSpeaking(at: .immediate)
                    self.clearSession()
                }
            }
        }
    }

    private func deactivateAudioSessionIfNeeded() {
        guard managesAudioSession else { return }
        Task.detached(priority: .userInitiated) {
            Self.performPlaybackSessionTeardown()
        }
    }

    /// `.playback` + `.spokenAudio`: music ducks under speech and recovers;
    /// other *spoken* audio (podcasts, audiobooks) pauses rather than becoming
    /// an unintelligible double-track, and resumes on our deactivation. NOT
    /// `.playAndRecord`+`.voiceChat` — voice-processing I/O degrades one-way
    /// playback; that config belongs to the future full-duplex voice mode.
    ///
    /// nonisolated static and called off-main: AVAudioSession calls block for
    /// hundreds of ms (see SpeechService.performEngineSetup — watchdog risk).
    private nonisolated static func performPlaybackSessionSetup() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func performPlaybackSessionTeardown() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Voice selection

    /// Testable stand-in for AVSpeechSynthesisVoice, whose traits can't be
    /// fabricated in unit tests.
    struct VoiceCandidate {
        let identifier: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality
        let isNovelty: Bool
        let isPersonal: Bool
    }

    /// Pure ranking. Quality beats region; exact locale wins ties: an en-GB
    /// Enhanced voice must beat an en-US Compact one for an en-US user (the
    /// old exact-`language ==` filter made prefix-siblings invisible).
    /// Novelty voices are never offered; Personal Voice is excluded until
    /// spec 018 R8's verification gate clears.
    nonisolated static func bestVoiceIdentifier(
        from candidates: [VoiceCandidate], currentLanguage: String
    ) -> String? {
        let prefix = currentLanguage.split(separator: "-").first.map(String.init)
            ?? currentLanguage
        let eligible = candidates.filter { !$0.isNovelty && !$0.isPersonal }
        let exact = eligible.filter { $0.language == currentLanguage }
        let related = eligible.filter {
            $0.language != currentLanguage && $0.language.hasPrefix(prefix + "-")
        }
        return exact.first { $0.quality == .premium }?.identifier
            ?? exact.first { $0.quality == .enhanced }?.identifier
            ?? related.first { $0.quality == .premium }?.identifier
            ?? related.first { $0.quality == .enhanced }?.identifier
            ?? exact.first?.identifier
    }

    private nonisolated static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().map {
            VoiceCandidate(
                identifier: $0.identifier,
                language: $0.language,
                quality: $0.quality,
                isNovelty: $0.voiceTraits.contains(.isNoveltyVoice),
                isPersonal: $0.voiceTraits.contains(.isPersonalVoice)
            )
        }
        if let identifier = bestVoiceIdentifier(from: candidates, currentLanguage: language),
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoicePlaybackService: AVSpeechSynthesizerDelegate {
    // Delegate callbacks may arrive off-main; hop and guard the generation so
    // callbacks from a stopped/replaced session can't revive stale state.

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard self.activeUtteranceIDs.contains(ObjectIdentifier(utterance)) else { return }
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.utteranceEnded(utterance) }
    }

    // isPaused flips eagerly in pauseSpeaking()/continueSpeaking() for snappy
    // UI; these delegate callbacks are confirmation, and they matter when the
    // pause originated outside the app (e.g. a future system-initiated pause).

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard self.activeUtteranceIDs.contains(ObjectIdentifier(utterance)) else { return }
            self.isPaused = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard self.activeUtteranceIDs.contains(ObjectIdentifier(utterance)) else { return }
            self.isPaused = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        // After stop() state is already cleared; a didCancel for an old
        // session's utterance won't be in activeUtteranceIDs and is ignored.
        Task { @MainActor in self.utteranceEnded(utterance) }
    }

    /// Internal (not fileprivate) so unit tests can drive the state machine
    /// synchronously instead of racing the delegate's main-actor hop.
    func utteranceEnded(_ utterance: AVSpeechUtterance) {
        guard activeUtteranceIDs.remove(ObjectIdentifier(utterance)) != nil else { return }
        endSessionIfDrained()
    }
}
