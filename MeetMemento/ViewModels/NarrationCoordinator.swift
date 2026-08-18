//
//  NarrationCoordinator.swift
//  MeetMemento
//
//  The state machine behind hands-free Narration Mode (Figma 302:618 /
//  409:5646): listen → auto-send on a significant pause → stream the reply
//  into the chat while narrating it per-sentence → listen again, until the
//  user exits.
//
//  Strictly HALF-duplex, by spec (06-speech-and-audio §B1: `.playAndRecord` +
//  `.voiceChat` is reserved for a future full-duplex mode). The loop therefore
//  sequences the audio session explicitly: recording is fully stopped and the
//  transcript consumed *before* a TTS session begins, and the TTS session is
//  fully drained (`speakingMessageID == nil`) **and its audio-session release
//  awaited** (`waitForSessionRelease`, spec 028 R3a) before the mic restarts.
//  It never leans on VoicePlaybackService's reactive "TTS yields to STT" sink —
//  that guard exists for the tap-a-mic-somewhere case, not for this loop.
//

import Combine
import Foundation
import os

// MARK: - Service seams (spec 028 R8)

/// What the narration loop needs from SpeechService — a seam so unit tests can
/// drive loop transitions without a mic (mirrors `SpeechSynthesizing`).
@MainActor
protocol NarrationSpeechListening: AnyObject {
    var audioLevel: Float { get }
    var bestAvailableTranscript: String { get }
    var partialTranscriptPublisher: AnyPublisher<String, Never> { get }
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    func isOwner(_ ownerId: String) -> Bool
    func startRecording(ownerId: String) async throws
    func stopRecording() async
    func cancelRecording() async
    func clearTranscription()
}

extension SpeechService: NarrationSpeechListening {
    var partialTranscriptPublisher: AnyPublisher<String, Never> {
        $partialTranscribedText.eraseToAnyPublisher()
    }
    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }
}

/// What the narration loop needs from VoicePlaybackService.
@MainActor
protocol NarrationVoicePlayback: AnyObject {
    var speakingMessageIDPublisher: AnyPublisher<UUID?, Never> { get }
    func beginUtteranceSession(for messageID: UUID, title: String?)
    func enqueue(sentence: String)
    func finishEnqueueing()
    func stop()
    func waitForSessionRelease() async
    /// Activate the playback session while the model thinks (spec 029 R4).
    func preactivateSession()
    /// Release an unused pre-activation (the send failed; back to listening).
    func releasePreactivatedSession()
    /// An external audio hand-off (mic teardown) every activation must follow
    /// (spec 029 Amendment A).
    func setActivationBarrier(_ task: Task<Void, Never>?)
    /// Resolve the TTS voice catalog if it is not already cached.
    func ensureVoiceCatalogWarmed() async
    /// Silent synthesizer spin-up so the first real `speak` is warm.
    func warmSynthesizer()
    /// Utterances currently speaking or buffered — used to prefetch a stable
    /// tail before the queue runs dry.
    var queuedSpeechCount: Int { get }
}

extension VoicePlaybackService: NarrationVoicePlayback {
    var speakingMessageIDPublisher: AnyPublisher<UUID?, Never> {
        $speakingMessageID.eraseToAnyPublisher()
    }
}

@MainActor
final class NarrationCoordinator: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        /// Mic open, waiting for (more) speech.
        case listening
        /// Mic stopping; transcript being consumed.
        case finalizing
        /// Message sent; no sentence has been spoken yet ("Thinking…").
        case awaitingResponse
        /// TTS session live (reply may still be streaming in behind it).
        case speaking
    }

    enum NarrationError: Equatable {
        case permissionDenied
        case recordingFailed
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    /// Live partial transcript, mirrored for the preview card.
    @Published private(set) var liveTranscript: String = ""
    /// The assistant message the current turn streams into — the view uses it
    /// to follow the reply while it is narrated.
    @Published private(set) var replyMessageID: UUID?
    /// How many chat messages existed when this narration session began. The
    /// narration transcript renders only messages appended after this index
    /// (the Figma flow starts clean; full history stays on the chat page).
    @Published private(set) var transcriptStartIndex: Int = 0
    @Published var errorKind: NarrationError?

    /// Canvas / QA only. Sets the visible phase without arming the mic or TTS,
    /// so `#Preview` can render Narration Mode as the user would see it.
    func seedPreview(phase: Phase, liveTranscript: String = "") {
        self.phase = phase
        self.liveTranscript = liveTranscript
        errorKind = nil
    }

    // MARK: - Tuning

    /// A pause this long (with the transcript stable) counts as "done talking".
    /// Deliberately conversational — SpeechService's own 20s silence timeout is
    /// journaling-paced and stays untouched. Expect to tune this by feel.
    static let autoSendPause: TimeInterval = 1.5
    /// The transcript-stability signal is primary; this amplitude gate only
    /// stops a send from firing mid-word. SpeechService publishes
    /// `min(1, rms * 3)`, where normal speech lands around 0.05–0.45.
    static let autoSendMaxAudioLevel: Float = 0.05
    /// Watchdog cadence — 4 Hz normally; the tick tightens to 10 Hz once the
    /// pause is close to firing, so auto-send jitter drops from ~125ms average
    /// to ~50ms without polling fast the whole time (spec 029 R4).
    private static let watchdogTick: UInt64 = 250_000_000
    private static let watchdogFineTick: UInt64 = 100_000_000
    /// How close to `autoSendPause` the fine tick kicks in.
    private static let watchdogFineWindow: TimeInterval = 0.3

    /// Pure tick chooser (unit-tested): fine cadence when the send decision is
    /// imminent, coarse otherwise.
    static func watchdogDelay(secondsSinceChange: TimeInterval) -> UInt64 {
        secondsSinceChange >= autoSendPause - watchdogFineWindow
            ? watchdogFineTick
            : watchdogTick
    }
    /// A listening turn that has produced NO signal (no partial, audio level
    /// pinned at exactly 0) for this long is dead — a live mic's smoothed RMS
    /// noise floor is nonzero, so exact 0 means the tap never delivered a
    /// buffer (spec 028 R4: the killed-session failure mode is silent).
    static let listeningLivenessTimeout: TimeInterval = 4.0
    /// Instance copy so unit tests can shrink the window; production never
    /// changes it.
    var livenessTimeout: TimeInterval = NarrationCoordinator.listeningLivenessTimeout

    // MARK: - Dependencies

    private let speechService: NarrationSpeechListening
    private let voiceService: NarrationVoicePlayback
    private weak var chatViewModel: ChatViewModel?

    private let speechOwnerId = "NarrationMode"

    /// Default-argument DI, same convention as `ChatViewModel.init(chatService:)`.
    init(
        speechService: NarrationSpeechListening = SpeechService.shared,
        voiceService: NarrationVoicePlayback = VoicePlaybackService.shared
    ) {
        self.speechService = speechService
        self.voiceService = voiceService
    }

    // MARK: - Internals

    private var cancellables = Set<AnyCancellable>()
    private var watchdog: Task<Void, Never>?
    private var chunker = StreamingSentenceChunker()
    /// Whether `beginUtteranceSession` has run for the current reply.
    private var ttsSessionBegun = false
    /// Set once the current reply has fully settled (final consumed) so the
    /// messages sink stops re-processing it.
    private var responseSettled = false
    /// When the transcript last changed — the pause detector's clock.
    private var lastTranscriptChange = Date()
    /// One silent retry after an unexpected recording drop before alerting.
    private var didRetryListening = false
    /// Liveness clock: when the current listening turn's mic actually armed.
    private var listenStartedAt = Date()
    /// True once the current listening turn showed any sign of life (nonzero
    /// audio level or a partial transcript).
    private var sawListeningActivity = false
    /// One silent re-arm per turn for a dead listen before alerting
    /// (spec 028 R4). Separate from `didRetryListening`, which resets on every
    /// successful start and so cannot bound a start-succeeds-then-dies loop.
    private var didRecoverDeadListen = false
    /// Guards the `$isRecording == false` sink: true only while a stop the
    /// coordinator did NOT initiate should be treated as an auto-send.
    private var expectsRecordingStop = false
    /// False after `stop()`. Async continuations (mic start/stop tasks) check
    /// this on resume so a torn-down session can't restart the loop.
    private var sessionActive = false
    /// Open `listen.rearm` signpost: TTS drained → mic live (spec 029 R1).
    private var rearmSignpostState: OSSignpostIntervalState?

    // MARK: - Pure decision helper (unit-tested)

    /// Whether a listening turn should auto-send now.
    static func shouldAutoSend(
        transcript: String,
        secondsSinceChange: TimeInterval,
        audioLevel: Float
    ) -> Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && secondsSinceChange >= autoSendPause
            && audioLevel < autoSendMaxAudioLevel
    }

    /// Whether the current listening turn is dead (spec 028 R4): never showed
    /// any activity, and the liveness window has elapsed.
    static func isListeningDead(
        sawActivity: Bool,
        secondsListening: TimeInterval,
        timeout: TimeInterval = listeningLivenessTimeout
    ) -> Bool {
        !sawActivity && secondsListening >= timeout
    }

    // MARK: - Lifecycle

    /// Enters the loop. Idempotent — a second call while active is a no-op.
    func start(chatViewModel: ChatViewModel) {
        guard phase == .idle else { return }
        self.chatViewModel = chatViewModel
        transcriptStartIndex = chatViewModel.messages.count
        errorKind = nil
        didRetryListening = false
        didRecoverDeadListen = false
        sessionActive = true
        subscribe()
        Task { await voiceService.ensureVoiceCatalogWarmed() }
        chatViewModel.prewarmNextTurn()
        beginListening()
    }

    /// Tears the loop down. The mic cancels (dropping any un-sent partial —
    /// the same escape-hatch semantics as dictation's X), TTS stops, but an
    /// in-flight chat send is deliberately left running: the reply keeps
    /// streaming into the transcript the user lands back on.
    func stop() {
        sessionActive = false
        watchdog?.cancel()
        watchdog = nil
        cancellables.removeAll()
        voiceService.stop()
        // A pre-activation with no session yet is invisible to stop() —
        // release it explicitly so exiting mid-"Thinking…" can't leak an
        // active playback session.
        voiceService.releasePreactivatedSession()
        if speechService.isOwner(speechOwnerId) {
            Task { await speechService.cancelRecording() }
        }
        replyMessageID = nil
        ttsSessionBegun = false
        responseSettled = false
        liveTranscript = ""
        phase = .idle
    }

    // MARK: - User actions

    /// The footer mic button. While listening it sends what's been heard
    /// without waiting out the pause; while speaking it barges in — cuts the
    /// narration and reopens the mic.
    func micTapped() {
        switch phase {
        case .listening:
            guard !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            finishListeningAndSend()
        case .speaking:
            // stop() clears speakingMessageID, which the loop-close sink
            // translates into a fresh listening turn.
            voiceService.stop()
        case .idle, .finalizing, .awaitingResponse:
            break
        }
    }

    /// Alert "Try Again" path.
    func retryListening() {
        guard phase == .idle || phase == .listening else { return }
        errorKind = nil
        didRetryListening = false
        didRecoverDeadListen = false
        beginListening()
    }

    // MARK: - Listening

    private func beginListening() {
        liveTranscript = ""
        lastTranscriptChange = Date()
        phase = .listening
        expectsRecordingStop = false

        Task {
            do {
                // The TTS session's release is async and, un-awaited, can land
                // AFTER our record session activates — deactivating it silently
                // (the "narration works once" bug, spec 028 R3a). Order it.
                // The previous turn's mic teardown is likewise no longer
                // awaited at send time (spec 029 Amendment A), so a fast
                // failure path could re-arm while it is still in flight —
                // order behind it too.
                await micReleaseTask?.value
                await voiceService.waitForSessionRelease()
                guard sessionActive else { return }
                try await speechService.startRecording(ownerId: speechOwnerId)
                guard sessionActive else {
                    // Torn down while the mic was spinning up — don't leave it open.
                    await speechService.cancelRecording()
                    return
                }
                expectsRecordingStop = true
                didRetryListening = false
                listenStartedAt = Date()
                sawListeningActivity = false
                if let state = rearmSignpostState {
                    rearmSignpostState = nil
                    PerfSignposts.speechLoop.endInterval("listen.rearm", state)
                    LiveTurnClock.shared.end(.listenRearm)
                    LiveTurnClock.shared.releaseAndLog()
                }
                chatViewModel?.prewarmNextTurn()
                startWatchdog()
            } catch let error as SpeechService.SpeechError {
                phase = .idle
                if case .permissionDenied = error {
                    errorKind = .permissionDenied
                } else {
                    errorKind = .recordingFailed
                }
            } catch {
                phase = .idle
                errorKind = .recordingFailed
            }
        }
    }

    /// 4 Hz pause detector. A timer-style loop rather than sinking on
    /// `audioLevel`: the level decays to exactly 0 in silence and stops
    /// publishing changes, which is the documented freeze trap
    /// (`DictationWaveform`) — a clock keeps the detector alive through
    /// silence, which is precisely the moment it must fire.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                guard let strongSelf = self else { return }
                let delay = Self.watchdogDelay(
                    secondsSinceChange: Date().timeIntervalSince(strongSelf.lastTranscriptChange)
                )
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !Task.isCancelled else { return }
                guard self.phase == .listening else { continue }
                // Liveness (spec 028 R4): any nonzero level or partial marks
                // the turn alive; a turn with no signal at all for the whole
                // window is a dead session (e.g. killed by a stale
                // setActive(false)) and hangs forever if left alone.
                if self.speechService.audioLevel > 0 || !self.liveTranscript.isEmpty {
                    self.sawListeningActivity = true
                } else if Self.isListeningDead(
                    sawActivity: self.sawListeningActivity,
                    secondsListening: Date().timeIntervalSince(self.listenStartedAt),
                    timeout: self.livenessTimeout
                ) {
                    self.recoverDeadListen()
                    return
                }
                // A send already in flight (barge-in while the previous reply
                // was still streaming): hold the turn until it settles rather
                // than dropping it on ChatViewModel's isLoading guard.
                if self.chatViewModel?.isLoading == true { continue }
                if Self.shouldAutoSend(
                    transcript: self.liveTranscript,
                    secondsSinceChange: Date().timeIntervalSince(self.lastTranscriptChange),
                    audioLevel: self.speechService.audioLevel
                ) {
                    self.finishListeningAndSend()
                }
            }
        }
    }

    /// A listening turn died silently (no signal for the liveness window):
    /// cancel the dead session and re-arm once; a second death in the same
    /// turn surfaces the error (spec 028 R4).
    private func recoverDeadListen() {
        guard phase == .listening else { return }
        watchdog?.cancel()
        watchdog = nil
        // The cancel below flips isRecording; don't let the unexpected-stop
        // sink treat it as a drop and race this recovery.
        expectsRecordingStop = false

        Task {
            await speechService.cancelRecording()
            guard sessionActive else { return }
            if !didRecoverDeadListen {
                didRecoverDeadListen = true
                beginListening()
            } else {
                phase = .idle
                errorKind = .recordingFailed
            }
        }
    }

    /// The in-flight mic engine teardown from the last listening turn. The
    /// send no longer waits for it (spec 029 Amendment A): the transcript is
    /// captured fast-partial and the model call dispatches immediately, hiding
    /// the ~100–400ms teardown behind model thinking. Everything that touches
    /// the shared audio session afterwards is ordered behind this task — the
    /// TTS pre-activation awaits it here, and VoicePlaybackService carries it
    /// as its activation barrier for the direct-activation path.
    private var micReleaseTask: Task<Void, Never>?

    private func finishListeningAndSend() {
        guard phase == .listening else { return }
        // Narrated-turn origin is mic-stop, not send — so the later
        // ChatViewModel beginTurn is a no-op (LiveTurnClock is idempotent).
        LiveTurnClock.shared.beginTurn(heldOpen: true)
        phase = .finalizing
        watchdog?.cancel()
        watchdog = nil
        expectsRecordingStop = false

        // Fast-partial by design: take the best transcript available right
        // now instead of waiting ~1.8s for finalization. The pause already
        // cost 1.5s; narration favors loop snappiness over a rare
        // last-word correction.
        let text = speechService.bestAvailableTranscript
        // Releases ownership AND clears isProcessing — the latter is what
        // VoicePlaybackService's isRecordingProvider checks, so this must
        // precede any TTS session.
        speechService.clearTranscription()

        let release = Task {
            LiveTurnClock.shared.start(.micStop)
            let micStopState = PerfSignposts.speechLoop.beginInterval("mic.stop")
            await speechService.stopRecording()
            PerfSignposts.speechLoop.endInterval("mic.stop", micStopState)
            LiveTurnClock.shared.end(.micStop)
        }
        micReleaseTask = release
        voiceService.setActivationBarrier(release)

        guard !text.isEmpty else {
            // Nothing to send — wait out the teardown, then listen again
            // (startRecording orders itself behind its own pending teardown).
            Task {
                await release.value
                guard sessionActive else { return }
                LiveTurnClock.shared.releaseAndLog()
                beginListening()
            }
            return
        }
        sendTurn(text)
        // Pre-activate TTS once the mic hand-off completes — still hidden
        // behind model thinking, which comfortably outlasts the teardown.
        Task { [weak self] in
            await release.value
            guard let self, self.sessionActive,
                  self.phase == .awaitingResponse || self.phase == .speaking else { return }
            self.voiceService.preactivateSession()
            self.voiceService.warmSynthesizer()
        }
    }

    // MARK: - Sending / response narration

    private func sendTurn(_ text: String) {
        guard let chatViewModel else {
            voiceService.releasePreactivatedSession()
            phase = .idle
            return
        }
        chunker = StreamingSentenceChunker()
        replyMessageID = nil
        ttsSessionBegun = false
        responseSettled = false
        // A fresh turn gets a fresh dead-listen recovery budget (spec 028 R4).
        didRecoverDeadListen = false
        liveTranscript = ""
        phase = .awaitingResponse
        // TTS pre-activation happens in finishListeningAndSend once the mic
        // hand-off completes (spec 029 Amendment A) — the model call below is
        // deliberately dispatched without waiting for either.
        chatViewModel.sendMessage(prompt: text)
    }

    /// Feed the streaming reply into the chunker and the chunker's output into
    /// TTS. Runs on every `messages` change while a turn is in flight.
    private func consumeReplyProgress() {
        guard let chatViewModel, !responseSettled,
              phase == .awaitingResponse || phase == .speaking else { return }
        guard let id = replyMessageID else { return }

        guard let message = chatViewModel.messages.first(where: { $0.id == id }) else {
            // Placeholder removed — the send failed outright. Listen again;
            // the user can rephrase. The pre-activated TTS session goes unused —
            // release it so the mic re-arm awaits a clean handoff.
            if chatViewModel.streamingAssistantMessageID == nil {
                responseSettled = true
                voiceService.releasePreactivatedSession()
                LiveTurnClock.shared.releaseAndLog()
                beginListening()
            }
            return
        }

        let body = message.aiOutputContent?.body ?? message.content
        // NOT `!message.isStreaming` alone: the freshly appended placeholder
        // has `isStreaming == false` (it flips on the first delta), so the
        // messages hop that runs before any delta would read the empty
        // placeholder as a settled empty reply — settling the turn and
        // skipping the entire narration. The turn is final only once the send
        // itself settled: performSend's defer moves the marker off this
        // message on success, error, and cancel alike.
        let isFinal = !message.isStreaming
            && chatViewModel.streamingAssistantMessageID != id
        // Prefetch a stable tail when TTS is about to run dry so the
        // synthesizer does not sit in dead air waiting for a period.
        let allowStableTail = ttsSessionBegun && voiceService.queuedSpeechCount <= 1
        let sentences = chunker.consume(body, isFinal: isFinal, allowStableTail: allowStableTail)

        for sentence in sentences {
            if !ttsSessionBegun {
                ttsSessionBegun = true
                PerfSignposts.speechLoop.emitEvent("chunk.firstSentence")
                LiveTurnClock.shared.mark(.firstSentence)
                voiceService.beginUtteranceSession(
                    for: id,
                    title: message.aiOutputContent?.heading1
                )
                phase = .speaking
            }
            voiceService.enqueue(sentence: sentence)
        }

        if isFinal {
            responseSettled = true
            if ttsSessionBegun {
                voiceService.finishEnqueueing()
            } else {
                // Reply settled with nothing speakable (empty or fully
                // stripped). Nothing will drain, so loop back directly —
                // releasing the pre-activated TTS session first.
                voiceService.releasePreactivatedSession()
                LiveTurnClock.shared.releaseAndLog()
                beginListening()
            }
        }
    }

    // MARK: - Subscriptions

    private func subscribe() {
        cancellables.removeAll()

        // Live transcript → preview card + pause clock.
        speechService.partialTranscriptPublisher
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self, self.speechService.isOwner(self.speechOwnerId) else { return }
                guard self.phase == .listening else { return }
                self.liveTranscript = text
                self.lastTranscriptChange = Date()
                if !text.isEmpty { self.sawListeningActivity = true }
            }
            .store(in: &cancellables)

        // Recording dropped without the coordinator asking (SpeechService's
        // internal 20s silence stop, or an engine error): salvage the words if
        // there are any, otherwise try listening once more before alerting.
        speechService.isRecordingPublisher
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self, self.phase == .listening, self.expectsRecordingStop else { return }
                self.expectsRecordingStop = false
                if !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // finishListeningAndSend re-stops an already-stopped
                    // recorder, which SpeechService treats as a no-op.
                    self.finishListeningAndSend()
                } else if !self.didRetryListening {
                    self.didRetryListening = true
                    self.beginListening()
                } else {
                    self.phase = .idle
                    self.errorKind = .recordingFailed
                }
            }
            .store(in: &cancellables)

        // Capture which assistant message this turn streams into.
        // (Set inside performSend after our sendMessage call, so it can't be a
        // stale value from a previous non-narration send.)
        // Also: nil with a vanished placeholder = failed send (handled in
        // consumeReplyProgress, which needs the messages array too).
        // chatViewModel outlives the coordinator's session (owned by
        // ContentView), so observing it directly is safe.
        chatViewModel?.$streamingAssistantMessageID
            .sink { [weak self] id in
                guard let self else { return }
                if let id {
                    guard self.phase == .awaitingResponse,
                          self.replyMessageID == nil else { return }
                    self.replyMessageID = id
                } else {
                    // The send settled (success, error, or cancel). Finality
                    // is read from this marker, and the settling itself may
                    // not touch `messages` (the defer's isStreaming flip
                    // no-ops when `.final` already cleared it) — so the
                    // messages sink alone can miss the last transition.
                    // Same one-hop deferral as that sink (willSet).
                    DispatchQueue.main.async { [weak self] in
                        self?.consumeReplyProgress()
                    }
                }
            }
            .store(in: &cancellables)

        chatViewModel?.$messages
            .sink { [weak self] _ in
                // Defer one runloop hop so `messages` (the sink fires on
                // willSet) is already updated when consumeReplyProgress reads it.
                DispatchQueue.main.async { [weak self] in
                    self?.consumeReplyProgress()
                }
            }
            .store(in: &cancellables)

        // Loop close: the TTS queue drained (or errored/was barged into) —
        // the reply is done being spoken, reopen the mic.
        voiceService.speakingMessageIDPublisher
            .removeDuplicates()
            .filter { $0 == nil }
            .sink { [weak self] _ in
                guard let self, self.phase == .speaking else { return }
                self.rearmSignpostState = PerfSignposts.speechLoop.beginInterval("listen.rearm")
                LiveTurnClock.shared.start(.listenRearm)
                self.beginListening()
            }
            .store(in: &cancellables)

        // Swallow the chat page's modal error alert while narrating. A failed
        // send already surfaces in the transcript ("Failed to send · Retry" on
        // the bubble) and the loop recovers by listening again — a modal over
        // a hands-free session is the one thing the user can't answer
        // hands-free. The flag is only reset while this session is active, so
        // chat-page behavior is untouched.
        chatViewModel?.$showingError
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.sessionActive else { return }
                self.chatViewModel?.showingError = false
            }
            .store(in: &cancellables)
    }
}
