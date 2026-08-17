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
//  fully drained (`speakingMessageID == nil`) before the mic restarts. It
//  never leans on VoicePlaybackService's reactive "TTS yields to STT" sink —
//  that guard exists for the tap-a-mic-somewhere case, not for this loop.
//

import Combine
import Foundation

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

    // MARK: - Tuning

    /// A pause this long (with the transcript stable) counts as "done talking".
    /// Deliberately conversational — SpeechService's own 20s silence timeout is
    /// journaling-paced and stays untouched. Expect to tune this by feel.
    static let autoSendPause: TimeInterval = 1.5
    /// The transcript-stability signal is primary; this amplitude gate only
    /// stops a send from firing mid-word. SpeechService publishes
    /// `min(1, rms * 3)`, where normal speech lands around 0.05–0.45.
    static let autoSendMaxAudioLevel: Float = 0.05
    /// Watchdog cadence — 4 Hz keeps worst-case added latency at 250ms.
    private static let watchdogTick: UInt64 = 250_000_000

    // MARK: - Dependencies

    private let speechService = SpeechService.shared
    private let voiceService = VoicePlaybackService.shared
    private weak var chatViewModel: ChatViewModel?

    private let speechOwnerId = "NarrationMode"

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
    /// Guards the `$isRecording == false` sink: true only while a stop the
    /// coordinator did NOT initiate should be treated as an auto-send.
    private var expectsRecordingStop = false
    /// False after `stop()`. Async continuations (mic start/stop tasks) check
    /// this on resume so a torn-down session can't restart the loop.
    private var sessionActive = false

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

    // MARK: - Lifecycle

    /// Enters the loop. Idempotent — a second call while active is a no-op.
    func start(chatViewModel: ChatViewModel) {
        guard phase == .idle else { return }
        self.chatViewModel = chatViewModel
        transcriptStartIndex = chatViewModel.messages.count
        errorKind = nil
        didRetryListening = false
        sessionActive = true
        subscribe()
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
                try await speechService.startRecording(ownerId: speechOwnerId)
                guard sessionActive else {
                    // Torn down while the mic was spinning up — don't leave it open.
                    await speechService.cancelRecording()
                    return
                }
                expectsRecordingStop = true
                didRetryListening = false
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
                try? await Task.sleep(nanoseconds: Self.watchdogTick)
                guard let self, !Task.isCancelled else { return }
                guard self.phase == .listening else { continue }
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

    private func finishListeningAndSend() {
        guard phase == .listening else { return }
        phase = .finalizing
        watchdog?.cancel()
        watchdog = nil
        expectsRecordingStop = false

        Task {
            await speechService.stopRecording()
            guard sessionActive else { return }
            // Fast-partial by design: take the best transcript available right
            // now instead of waiting ~1.8s for finalization. The pause already
            // cost 1.5s; narration favors loop snappiness over a rare
            // last-word correction.
            let text = speechService.bestAvailableTranscript
            // Releases ownership AND clears isProcessing — the latter is what
            // VoicePlaybackService's isRecordingProvider checks, so this must
            // precede any TTS session.
            speechService.clearTranscription()

            guard !text.isEmpty else {
                beginListening()
                return
            }
            sendTurn(text)
        }
    }

    // MARK: - Sending / response narration

    private func sendTurn(_ text: String) {
        guard let chatViewModel else {
            phase = .idle
            return
        }
        chunker = StreamingSentenceChunker()
        replyMessageID = nil
        ttsSessionBegun = false
        responseSettled = false
        liveTranscript = ""
        phase = .awaitingResponse
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
            // the user can rephrase.
            if chatViewModel.streamingAssistantMessageID == nil {
                responseSettled = true
                beginListening()
            }
            return
        }

        let body = message.aiOutputContent?.body ?? message.content
        let isFinal = !message.isStreaming
        let sentences = chunker.consume(body, isFinal: isFinal)

        for sentence in sentences {
            if !ttsSessionBegun {
                ttsSessionBegun = true
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
                // stripped). Nothing will drain, so loop back directly.
                beginListening()
            }
        }
    }

    // MARK: - Subscriptions

    private func subscribe() {
        cancellables.removeAll()

        // Live transcript → preview card + pause clock.
        speechService.$partialTranscribedText
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self, self.speechService.isOwner(self.speechOwnerId) else { return }
                guard self.phase == .listening else { return }
                self.liveTranscript = text
                self.lastTranscriptChange = Date()
            }
            .store(in: &cancellables)

        // Recording dropped without the coordinator asking (SpeechService's
        // internal 20s silence stop, or an engine error): salvage the words if
        // there are any, otherwise try listening once more before alerting.
        speechService.$isRecording
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
            .compactMap { $0 }
            .sink { [weak self] id in
                guard let self, self.phase == .awaitingResponse,
                      self.replyMessageID == nil else { return }
                self.replyMessageID = id
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
        voiceService.$speakingMessageID
            .removeDuplicates()
            .filter { $0 == nil }
            .sink { [weak self] _ in
                guard let self, self.phase == .speaking else { return }
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
