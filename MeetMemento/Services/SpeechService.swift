//
//  SpeechService.swift
//  MeetMemento
//
//  Native iOS speech-to-text. Capture engine is SpeechAnalyzer /
//  SpeechTranscriber / SpeechDetector (spec 018 R1). Permission still uses
//  the Speech framework authorization API.
//

import Foundation
import Speech
import AVFoundation


@MainActor
final class SpeechService: ObservableObject {
    static let shared = SpeechService()

    @Published var isRecording = false
    @Published var isProcessing = false
    /// Finalized transcript for the current (or just-finished) session.
    @Published var transcribedText = ""
    /// Live running utterance (committed segments + current volatile tail).
    @Published var partialTranscribedText = ""
    @Published var errorMessage: String?
    @Published var currentDuration: TimeInterval = 0
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    /// Real-time audio level 0...1 for voice-reactive UI (e.g. wave visualizer).
    @Published var audioLevel: Float = 0
    /// Spec 034: SpeechDetector VAD bit for conversation barge-in.
    @Published var speechDetected: Bool = false
    /// Locale-model download progress (first-run, spec 018 R1).
    @Published var assetState: TranscriptionAssetState = .missing

    /// Tracks consecutive silence duration for auto-stop
    private var silenceStartTime: Date?
    private let silenceThreshold: Float = 0.02  // Audio level below this = silence
    /// Reflective pauses are common in journaling; keep this generous so silence
    /// does not truncate mid-thought and force a bad auto-finalize.
    private let silenceTimeout: TimeInterval = 20.0

    /// Identifier of the view that initiated the current recording session.
    /// Used to prevent multiple views from reacting to the same transcription.
    @Published private(set) var activeSessionOwner: String?

    enum AuthorizationStatus {
        case notDetermined, denied, authorized
    }

    enum SpeechError: LocalizedError {
        case notAvailable
        case onDeviceUnavailable
        case permissionDenied
        case audioSessionFailed(String)
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "Speech recognition not available"
            case .onDeviceUnavailable:
                return """
                On-device speech recognition isn’t available for this language right now. \
                You can type instead, or download the language in Settings → General → Keyboard → Dictation.
                """
            case .permissionDenied: return "Microphone or speech recognition permission denied"
            case .audioSessionFailed(let msg): return "Audio session error: \(msg)"
            case .engineStartFailed(let msg): return "Could not start recording: \(msg)"
            }
        }
    }

    private var durationTimer: Timer?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private var smoothedLevel: Float = 0
    /// When true, recognition callbacks are ignored (cancel path / teardown).
    private var ignoreRecognitionResults = false
    /// Bumped on every start/cancel so stale callbacks cannot revive a finished session.
    private var sessionGeneration: UInt64 = 0
    private let analyzerEngine = SpeechAnalyzerEngine()
    private var pendingTeardown: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var isPausedForInterruption = false
    /// Last capture style. Conversation pauses the analyzer between turns
    /// instead of tearing it down; dictation still finishes on stop.
    private var activeStyle: TranscriptionStyle = .dictation
    /// Segment finals + current volatile, published as one utterance.
    private var running = RunningTranscript()

    private init() {
        observeInterruptions()
    }

    // MARK: - Audio level (for voice-reactive UI)

    nonisolated static func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        if let channelData = buffer.floatChannelData {
            let ptr = channelData[0]
            var sum: Float = 0
            for i in 0..<frameLength {
                let s = ptr[i]
                sum += s * s
            }
            let rms = sqrt(sum / Float(frameLength))
            return min(1, rms * 3)
        }
        if let channelData = buffer.int16ChannelData {
            let ptr = channelData[0]
            var sum: Float = 0
            let scale: Float = 1 / 32768
            for i in 0..<frameLength {
                let s = Float(ptr[i]) * scale
                sum += s * s
            }
            let rms = sqrt(sum / Float(frameLength))
            return min(1, rms * 3)
        }
        return 0
    }

    private func updateAudioLevel(_ rms: Float) {
        smoothedLevel = smoothedLevel * 0.3 + rms * 0.7
        audioLevel = smoothedLevel

        if isRecording {
            if smoothedLevel < silenceThreshold {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                } else if let start = silenceStartTime,
                          Date().timeIntervalSince(start) >= silenceTimeout {
                    Task { @MainActor in
                        await self.stopRecording()
                    }
                }
            } else {
                silenceStartTime = nil
            }
        }
    }

    // MARK: - Authorization

    /// Permission still types through this API; recognition itself does not.
    static func mapSpeechAuth(_ status: SFSpeechRecognizerAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> AuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    let auth = Self.mapSpeechAuth(status)
                    self?.authorizationStatus = auth
                    continuation.resume(returning: auth)
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording

    func startRecording(ownerId: String, style: TranscriptionStyle = .dictation) async throws {
        if analyzerEngine.isCapturePaused, activeStyle == style {
            do {
                try await resumeCapture(ownerId: ownerId, style: style)
                return
            } catch {
                await analyzerEngine.cancel()
            }
        }

        teardownEngine(clearOwnership: true)

        errorMessage = nil
        transcribedText = ""
        partialTranscribedText = ""
        running.reset()
        speechDetected = false
        activeSessionOwner = ownerId
        activeStyle = style
        silenceStartTime = nil
        ignoreRecognitionResults = false
        sessionGeneration &+= 1
        let generation = sessionGeneration

        let knownAuth = Self.mapSpeechAuth(SFSpeechRecognizer.authorizationStatus())
        let speechAuth: AuthorizationStatus
        if knownAuth == .notDetermined {
            speechAuth = await requestAuthorization()
        } else {
            authorizationStatus = knownAuth
            speechAuth = knownAuth
        }
        if speechAuth != .authorized {
            authorizationStatus = speechAuth
            errorMessage = SpeechError.permissionDenied.errorDescription
            activeSessionOwner = nil
            throw SpeechError.permissionDenied
        }

        let micGranted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micGranted = true
        case .denied: micGranted = false
        default: micGranted = await requestMicrophonePermission()
        }
        if !micGranted {
            errorMessage = SpeechError.permissionDenied.errorDescription
            activeSessionOwner = nil
            throw SpeechError.permissionDenied
        }

        guard SpeechTranscriber.isAvailable else {
            errorMessage = SpeechError.notAvailable.errorDescription
            activeSessionOwner = nil
            throw SpeechError.notAvailable
        }

        let locale = Locale.current
        assetState = await analyzerEngine.assetState(for: locale, style: style)
        if assetState == .missing || assetState == .downloading {
            await analyzerEngine.ensureAssets(for: locale, style: style)
            assetState = await analyzerEngine.assetState(for: locale, style: style)
        }
        if assetState == .unsupported {
            errorMessage = SpeechError.onDeviceUnavailable.errorDescription
            activeSessionOwner = nil
            throw SpeechError.onDeviceUnavailable
        }

        await pendingTeardown?.value

        do {
            try await analyzerEngine.start(
                locale: locale,
                style: style,
                onUpdate: { [weak self] update in
                    self?.handleUpdate(update, generation: generation)
                },
                onLevel: { [weak self] rms in
                    Task { @MainActor in
                        self?.updateAudioLevel(rms)
                    }
                },
                onSpeechDetected: { [weak self] present in
                    Task { @MainActor in
                        self?.speechDetected = present
                        ConversationAudioController.shared.handleVoiceActivity(present)
                    }
                }
            )
        } catch {
            let msg = error.localizedDescription
            errorMessage = SpeechError.engineStartFailed(msg).errorDescription
            isProcessing = false
            activeSessionOwner = nil
            throw SpeechError.engineStartFailed(msg)
        }

        isProcessing = true
        isRecording = true
        let startTime = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
        if let durationTimer {
            RunLoop.main.add(durationTimer, forMode: .common)
        }
    }

    /// Re-arm a paused conversation capture without reallocating SpeechAnalyzer.
    private func resumeCapture(ownerId: String, style: TranscriptionStyle) async throws {
        errorMessage = nil
        transcribedText = ""
        partialTranscribedText = ""
        running.reset()
        speechDetected = false
        activeSessionOwner = ownerId
        activeStyle = style
        silenceStartTime = nil
        ignoreRecognitionResults = false
        sessionGeneration &+= 1
        let generation = sessionGeneration

        await pendingTeardown?.value

        let resumed = try analyzerEngine.resumeCapture(
            onUpdate: { [weak self] update in
                self?.handleUpdate(update, generation: generation)
            },
            onLevel: { [weak self] rms in
                Task { @MainActor in
                    self?.updateAudioLevel(rms)
                }
            },
            onSpeechDetected: { [weak self] present in
                Task { @MainActor in
                    self?.speechDetected = present
                    ConversationAudioController.shared.handleVoiceActivity(present)
                }
            }
        )
        guard resumed else {
            throw SpeechError.engineStartFailed("speech analyzer was not paused")
        }

        isProcessing = true
        isRecording = true
        let startTime = Date()
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
        if let durationTimer {
            RunLoop.main.add(durationTimer, forMode: .common)
        }
    }

    func stopRecording() async {
        guard isRecording else {
            isRecording = false
            return
        }

        durationTimer?.invalidate()
        durationTimer = nil
        currentDuration = 0
        silenceStartTime = nil
        audioLevel = 0
        smoothedLevel = 0
        isRecording = false

        if activeStyle == .conversation {
            // Keep SpeechAnalyzer allocated across narration turns. Mic tap
            // is down (half-duplex) so TTS can take playback; resume on re-arm.
            analyzerEngine.pauseCapture()
            isProcessing = false
            return
        }

        await analyzerEngine.finish()
        scheduleFinalizationTimeout()
    }

    func cancelRecording() async {
        ignoreRecognitionResults = true
        sessionGeneration &+= 1
        teardownEngine(clearOwnership: true)
        pendingTeardown = Task { await analyzerEngine.cancel() }
        await pendingTeardown?.value

        transcribedText = ""
        partialTranscribedText = ""
        running.reset()
        errorMessage = nil
        isProcessing = false
        isRecording = false
        currentDuration = 0
        silenceStartTime = nil
        audioLevel = 0
        smoothedLevel = 0
        speechDetected = false
    }

    var bestAvailableTranscript: String {
        running.display
    }

    func isOwner(_ ownerId: String) -> Bool {
        activeSessionOwner == ownerId
    }

    func clearTranscription() {
        transcribedText = ""
        partialTranscribedText = ""
        running.reset()
        activeSessionOwner = nil
        isProcessing = false
    }

    // MARK: - Updates

    private func handleUpdate(_ update: TranscriptionUpdate, generation: UInt64) {
        guard generation == sessionGeneration, !ignoreRecognitionResults else { return }
        running.apply(update)
        transcribedText = running.committed
        let display = running.display
        // Never flash empty while committed text remains — a segment final
        // used to clear the partial and empty the live bubble.
        if !display.isEmpty {
            partialTranscribedText = display
        }
        if case .finalized = update, !isRecording {
            finalizationTimeoutTask?.cancel()
            finalizationTimeoutTask = nil
            isProcessing = false
            let leftover = AudioAssetStore.applyRetentionAfterTranscription(assetID: nil)
            _ = leftover
        }
    }

    private func scheduleFinalizationTimeout() {
        finalizationTimeoutTask?.cancel()
        let generation = sessionGeneration
        finalizationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard generation == self.sessionGeneration else { return }
            guard self.isProcessing else { return }
            if self.running.display.isEmpty { return }
            self.running.apply(.finalized(""))
            self.transcribedText = self.running.committed
            self.partialTranscribedText = self.running.display
            self.isProcessing = false
            AppLogger.log("⚠️ [SpeechService] Finalization timed out; promoted partial transcript if available")
        }
    }

    private func teardownEngine(clearOwnership: Bool) {
        durationTimer?.invalidate()
        durationTimer = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        pendingTeardown = Task { await analyzerEngine.cancel() }
        audioLevel = 0
        smoothedLevel = 0
        silenceStartTime = nil
        currentDuration = 0
        if clearOwnership {
            activeSessionOwner = nil
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            guard isRecording else { return }
            isPausedForInterruption = true
            analyzerEngine.pause()
            errorMessage = "Paused for your call. Everything you said is safe."
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if isPausedForInterruption, options.contains(.shouldResume) {
                try? analyzerEngine.resume()
                isPausedForInterruption = false
                errorMessage = nil
            } else if isPausedForInterruption {
                Task { await stopRecording() }
                isPausedForInterruption = false
            }
        @unknown default:
            break
        }
    }
}
