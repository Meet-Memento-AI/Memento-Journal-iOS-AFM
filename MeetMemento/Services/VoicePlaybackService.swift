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

    /// The engine actually producing speech — neural or system (spec 031 R2).
    /// This service does not know which, and must not learn.
    private let engine: UtteranceEngine
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
    private var activeUtteranceIDs = Set<UtteranceID>()
    /// Set by `finishEnqueueing()`: when the queue drains after this, the
    /// session ends. Without it, `didFinish` of the last *currently queued*
    /// utterance would prematurely end a streaming session.
    private var inputComplete = false
    /// Bumped on every begin/stop so a late delegate callback from a cancelled
    /// session can't revive state (SpeechService's proven pattern).
    private var sessionGeneration: UInt64 = 0
    /// The in-flight audio-session release, if any (spec 028 R3). Stored so the
    /// next activation — ours via `activateAudioSessionIfNeeded`, or the mic's
    /// via `waitForSessionRelease` — can await it instead of racing it. An
    /// un-awaited `setActive(false)` landing after the next `setActive(true)`
    /// silently kills the new session (the "narration works once" bug).
    private var sessionReleaseTask: Task<Void, Never>?

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
            engineFactory: { voiceProvider in
                let system = SystemUtteranceEngine(synthesizer: synthesizer,
                                                   voiceProvider: voiceProvider)
                // Neural is the only path the shipping roster can take: every
                // voice in VoiceCatalog is a Supertonic style, and the system
                // engine survives solely as the fallback inside it (030 R5).
                return NeuralUtteranceEngine(
                    playback: TTSPlayback(managesAudioSession: false),
                    fallback: system,
                    styleIDProvider: {
                        VoiceCatalog.resolve(
                            persistedID: PreferencesService.shared.selectedVoiceIdentifier
                        ).id
                    }
                )
            },
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

    /// Test seam. The factory receives the voice resolver so the engine can be
    /// built during `init` without capturing a not-yet-initialised `self`.
    init(
        engineFactory: (@escaping () -> AVSpeechSynthesisVoice?) -> UtteranceEngine,
        managesAudioSession: Bool,
        isRecordingProvider: @escaping () -> Bool = { false },
        rateProvider: @escaping () -> Float = { SpeechRatePreset.brisk.rawValue }
    ) {
        let voiceBox = VoiceBox()
        self.engine = engineFactory({ voiceBox.resolve?() })
        self.managesAudioSession = managesAudioSession
        self.isRecordingProvider = isRecordingProvider
        self.rateProvider = rateProvider
        super.init()
        voiceBox.resolve = { [weak self] in self?.voice }
        engine.engineDelegate = self
    }

    /// Breaks the initialisation cycle between the service (which owns the
    /// AVSpeech voice cache, because three other screens warm it) and the engine
    /// (which needs to read it).
    private final class VoiceBox {
        var resolve: (() -> AVSpeechSynthesisVoice?)?
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
        engine.stopAll()
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
        engine.pause()
        updateNowPlayingRate(0.0)
    }

    /// Resumes a paused session from the paused word.
    func continueSpeaking() {
        guard speakingMessageID != nil, isPaused else { return }
        isPaused = false
        engine.resume()
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
            engine.stopAll()
        }
        speakingMessageID = messageID
        isSpeaking = false
        isPaused = false
        errorMessage = nil
        activeUtteranceIDs.removeAll()
        pendingUtterances.removeAll()
        inputComplete = false
        beginSessionActivation()
        // The lock-screen publish is an XPC hop to the media server — defer it
        // one hop so it never sits between session begin and the first
        // utterance (spec 029 Amendment A).
        Task { @MainActor [weak self] in
            guard let self, self.speakingMessageID == messageID else { return }
            self.publishNowPlaying(title: title)
        }
    }

    /// Enqueue one sentence/paragraph as its own utterance. Sanitizes
    /// internally — the single choke point, so every caller (tap today, the
    /// chunker later) produces clean speech. AVSpeechSynthesizer queues
    /// utterances FIFO natively. Until the audio session activation lands,
    /// utterances buffer in `pendingUtterances` (spec 029 R4: speaking before
    /// `setActive(true)` completes clips the first word).
    func enqueue(sentence: String) {
        guard speakingMessageID != nil else { return }
        let text = SpeechTextSanitizer.sanitize(sentence)
        guard !text.isEmpty else { return }

        // Voice, rate clamping and utterance construction now belong to the
        // engine. What stays here is the rate *preference* and the pacing
        // decision, because both are the app's, not the synthesizer's.
        let request = UtteranceRequest(
            id: UtteranceID(),
            text: text,
            // User preference (SpeechRatePreset); default Brisk 0.53 — system 0.5
            // reads slightly slow for conversational AI.
            rate: rateProvider(),
            // A short breath between parts (heading → body, sentence → sentence).
            // Was 0.25 — measurably dead air across a multi-sentence reply
            // (spec 029 R4).
            postDelay: 0.1
        )
        activeUtteranceIDs.insert(request.id)
        if activationComplete {
            engine.speak(request)
        } else {
            pendingUtterances.append(request)
        }
    }

    /// Marks input complete: once the synthesizer queue drains past this,
    /// the session ends and state clears.
    func finishEnqueueing() {
        guard speakingMessageID != nil else { return }
        inputComplete = true
        endSessionIfDrained()
    }

    // Settings previews are no longer served here. They render through
    // SupertonicEngine directly (spec 033 R2), so this service no longer needs a
    // synthetic preview session id or a second preview sentence — one sentence,
    // owned by VoiceSettingsView, is now the only one.

    // MARK: - Session activation (spec 029 R4)

    /// True once the playback audio session is active for the current
    /// utterance session (always true when `managesAudioSession` is false —
    /// unit tests). While false, `enqueue` buffers into `pendingUtterances`.
    private var activationComplete = true
    /// Utterances enqueued before activation landed, spoken in order once it does.
    private var pendingUtterances: [UtteranceRequest] = []
    /// The in-flight `setActive(true)` (nil error = success). Shared between
    /// pre-activation and session begin so narration can pay this cost while
    /// the model is still thinking.
    private var activationTask: Task<Error?, Never>?

    /// An audio-session hand-off owned by ANOTHER service (the mic's engine
    /// teardown) that any playback activation must strictly follow. Narration
    /// sets it when it dispatches a turn without awaiting the mic teardown
    /// (spec 029 Amendment A) — the half-duplex ordering invariant (spec 028
    /// R2/R3) then holds through this barrier instead of through the caller's
    /// await. Awaiting an already-completed task is instant, so it never needs
    /// clearing.
    private var externalActivationBarrier: Task<Void, Never>?

    func setActivationBarrier(_ task: Task<Void, Never>?) {
        externalActivationBarrier = task
    }

    private func startPlaybackActivation() -> Task<Error?, Never> {
        let release = sessionReleaseTask
        let barrier = externalActivationBarrier
        return Task.detached(priority: .userInitiated) {
            await barrier?.value
            await release?.value
            LiveTurnClock.shared.start(.ttsActivate)
            let state = PerfSignposts.speechLoop.beginInterval("tts.activate")
            defer {
                PerfSignposts.speechLoop.endInterval("tts.activate", state)
                LiveTurnClock.shared.end(.ttsActivate)
            }
            do { try Self.performPlaybackSessionSetup(); return nil }
            catch { return error }
        }
    }

    /// Activates the playback session ahead of a TTS session — narration calls
    /// this the moment a turn is dispatched (mic already released), so the
    /// activation cost hides behind model thinking time. Generation-guarded by
    /// the begin/stop machinery; if no session follows, call
    /// `releasePreactivatedSession()`.
    func preactivateSession() {
        guard managesAudioSession, activationTask == nil, speakingMessageID == nil,
              !isRecordingProvider() else { return }
        activationTask = startPlaybackActivation()
    }

    /// Releases a pre-activated session that ended up unused (the send failed
    /// and narration went back to listening). Ordered behind the activation
    /// and guarded like every release (`shouldReleaseAudioSession`).
    func releasePreactivatedSession() {
        guard speakingMessageID == nil, let pending = activationTask else { return }
        activationTask = nil
        let scheduledGeneration = sessionGeneration
        sessionReleaseTask = Task.detached(priority: .userInitiated) { [weak self] in
            _ = await pending.value
            let shouldRelease = await MainActor.run { [weak self] () -> Bool in
                guard let self else { return true }
                return Self.shouldReleaseAudioSession(
                    scheduledGeneration: scheduledGeneration,
                    currentGeneration: self.sessionGeneration,
                    isRecording: self.isRecordingProvider(),
                    speakingMessageID: self.speakingMessageID
                )
            }
            guard shouldRelease else { return }
            Self.performPlaybackSessionTeardown()
        }
    }

    /// Ensures the session is (or becomes) active for the current utterance
    /// session, then flushes any buffered utterances in order. Adopts a
    /// pre-activation when one is in flight.
    private func beginSessionActivation() {
        guard managesAudioSession else {
            activationComplete = true
            return
        }
        activationComplete = false
        let generation = sessionGeneration
        let task = activationTask ?? startPlaybackActivation()
        activationTask = task
        Task { [weak self] in
            let failure = await task.value
            guard let self, self.sessionGeneration == generation else { return }
            self.activationTask = nil
            if let failure {
                self.errorMessage = "Audio playback unavailable: \(failure.localizedDescription)"
                self.engine.stopAll()
                self.clearSession()
            } else {
                self.activationComplete = true
                let queued = self.pendingUtterances
                self.pendingUtterances.removeAll()
                queued.forEach { self.engine.speak($0) }
            }
        }
    }

    /// Resolves the voice catalog off the main thread and caches the result —
    /// the first `AVSpeechSynthesisVoice.speechVoices()` call is slow and used
    /// to land on the main thread at first narrated reply (spec 029 R5).
    func ensureVoiceCatalogWarmed() async {
        await warmVoiceCatalog()
    }

    /// Spins the engine up so the first real sentence is not the one that pays
    /// load cost — a silent utterance for the system engine, graph loading for
    /// the neural one. Generation-guarded: a barge-in or cancel that bumps
    /// `sessionGeneration` drops the warm-up unused.
    func warmSynthesizer() {
        let generation = sessionGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.warmVoiceCatalog()
            guard self.sessionGeneration == generation, self.speakingMessageID == nil else { return }
            if let pending = self.activationTask {
                _ = await pending.value
            }
            guard self.sessionGeneration == generation, self.speakingMessageID == nil else { return }
            self.engine.warm()
        }
    }

    var queuedSpeechCount: Int {
        activeUtteranceIDs.count + pendingUtterances.count
    }

    func warmVoiceCatalog() async {
        guard !voiceCacheValid else { return }
        let identifier = PreferencesService.shared.selectedVoiceIdentifier
        let resolved = await Task.detached(priority: .utility) { () -> AVSpeechSynthesisVoice? in
            if let identifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
                return chosen
            }
            return Self.bestVoice()
        }.value
        if !voiceCacheValid {
            cachedVoice = resolved
            voiceCacheValid = true
        }
    }

    /// Quality of the voice narration will actually use (nil until resolvable).
    /// Drives the one-time compact-voice nudge (spec 029 R8) — call after
    /// `warmVoiceCatalog()` so this never triggers the slow catalog load.
    var resolvedVoiceQuality: AVSpeechSynthesisVoiceQuality? {
        guard voiceCacheValid else { return nil }
        return cachedVoice?.quality
    }

    // MARK: - Session bookkeeping

    private func clearSession() {
        speakingMessageID = nil
        isSpeaking = false
        isPaused = false
        activeUtteranceIDs.removeAll()
        pendingUtterances.removeAll()
        inputComplete = false
        activationComplete = !managesAudioSession
        deactivateAudioSessionIfNeeded()
        // Deferred like publishNowPlaying — the clear must not delay the
        // listen re-arm the drain publisher just triggered.
        Task { @MainActor [weak self] in
            guard let self, self.speakingMessageID == nil else { return }
            self.clearNowPlaying()
        }
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

    private func deactivateAudioSessionIfNeeded() {
        guard managesAudioSession else { return }
        let scheduledGeneration = sessionGeneration
        // A stop can land while activation is still in flight — the release
        // must run strictly after that setActive(true), or it deactivates
        // nothing and the session leaks active.
        let pendingActivation = activationTask
        activationTask = nil
        sessionReleaseTask = Task.detached(priority: .userInitiated) { [weak self] in
            _ = await pendingActivation?.value
            // Re-check on the main actor at execution time, not schedule time:
            // by the time this runs, a new TTS session may have begun (barge-in
            // → immediate next reply) or a recording may already own the shared
            // session (inline dictation after the yield sink's stop()). In
            // either case deactivating would kill a live session that is no
            // longer ours to release.
            let shouldRelease = await MainActor.run { [weak self] () -> Bool in
                guard let self else { return true }
                return Self.shouldReleaseAudioSession(
                    scheduledGeneration: scheduledGeneration,
                    currentGeneration: self.sessionGeneration,
                    isRecording: self.isRecordingProvider(),
                    speakingMessageID: self.speakingMessageID
                )
            }
            guard shouldRelease else { return }
            Self.performPlaybackSessionTeardown()
        }
    }

    /// Awaits the in-flight session release, if any (spec 028 R3a). The
    /// narration loop calls this before re-arming the mic so the record
    /// session's setActive(true) is strictly ordered after our
    /// setActive(false). Invariant: `clearSession()` assigns
    /// `sessionReleaseTask` synchronously on the main actor, before any Task
    /// spawned by the `speakingMessageID = nil` willSet sink can run — so a
    /// caller reacting to that publish always observes the fresh task here.
    func waitForSessionRelease() async {
        await sessionReleaseTask?.value
    }

    /// Pure decision: may a release scheduled by generation
    /// `scheduledGeneration` deactivate the shared audio session now?
    /// False whenever the session is no longer ours to release: the playback
    /// generation moved on (a newer TTS session owns it), a recording is live
    /// (STT owns it), or a speaking session is active.
    nonisolated static func shouldReleaseAudioSession(
        scheduledGeneration: UInt64,
        currentGeneration: UInt64,
        isRecording: Bool,
        speakingMessageID: UUID?
    ) -> Bool {
        scheduledGeneration == currentGeneration
            && !isRecording
            && speakingMessageID == nil
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

        if let premiumExact = exact.first(where: { $0.quality == .premium }) {
            return premiumExact.identifier
        }
        if let enhancedExact = exact.first(where: { $0.quality == .enhanced }) {
            return enhancedExact.identifier
        }
        if let premiumRelated = related.first(where: { $0.quality == .premium }) {
            return premiumRelated.identifier
        }
        if let enhancedRelated = related.first(where: { $0.quality == .enhanced }) {
            return enhancedRelated.identifier
        }
        return exact.first?.identifier
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

extension VoicePlaybackService: UtteranceEngineDelegate {
    // The engine reports on the main actor and the ids it reports are the ones
    // handed to it, so these no longer hop threads or unwrap object identity.
    // Staleness is still handled the same way it always was: an id that is not
    // in `activeUtteranceIDs` belongs to a session that has already ended, and
    // is ignored.

    func utteranceDidStart(_ id: UtteranceID) {
        guard activeUtteranceIDs.contains(id) else { return }
        if !isSpeaking {
            // First audio of the session — the moment the user hears the
            // reply begin (spec 029 R1 `tts.firstAudio`).
            PerfSignposts.speechLoop.emitEvent("tts.firstAudio")
            LiveTurnClock.shared.mark(.ttsFirstAudio)
        }
        isSpeaking = true
    }

    /// Spoken to completion, or cancelled — the session only tracks whether an
    /// utterance is still outstanding, so both mean the same thing here.
    ///
    /// Internal (not private) so unit tests can drive the state machine directly
    /// instead of racing a real engine.
    func utteranceDidEnd(_ id: UtteranceID) {
        guard activeUtteranceIDs.remove(id) != nil else { return }
        endSessionIfDrained()
    }

    // isPaused flips eagerly in pauseSpeaking()/continueSpeaking() for snappy
    // UI; these are confirmation, and they matter when the pause originated
    // outside the app.

    func utteranceDidPause(_ id: UtteranceID) {
        guard activeUtteranceIDs.contains(id) else { return }
        isPaused = true
    }

    func utteranceDidResume(_ id: UtteranceID) {
        guard activeUtteranceIDs.contains(id) else { return }
        isPaused = false
    }
}
