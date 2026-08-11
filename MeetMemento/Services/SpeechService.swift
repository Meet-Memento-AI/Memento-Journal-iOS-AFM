//
//  SpeechService.swift
//  MeetMemento
//
//  Native iOS speech-to-text using Speech framework and AVFoundation.
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
    /// Live volatile hypothesis while recording. Cleared when a final arrives or the session ends.
    @Published var partialTranscribedText = ""
    @Published var errorMessage: String?
    @Published var currentDuration: TimeInterval = 0
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    /// Real-time audio level 0...1 for voice-reactive UI (e.g. wave visualizer).
    @Published var audioLevel: Float = 0

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

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var durationTimer: Timer?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private let audioQueue = DispatchQueue(label: "com.meetmemento.speech.audio")
    private var smoothedLevel: Float = 0
    /// When true, recognition callbacks are ignored (cancel path / teardown).
    private var ignoreRecognitionResults = false
    /// Bumped on every start/cancel so stale callbacks cannot revive a finished session.
    private var sessionGeneration: UInt64 = 0

    private init() {}

    // MARK: - Audio level (for voice-reactive UI)

    private nonisolated static func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
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

        // Silence detection for auto-stop
        if isRecording {
            if smoothedLevel < silenceThreshold {
                // Start tracking silence if not already
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                } else if let start = silenceStartTime,
                          Date().timeIntervalSince(start) >= silenceTimeout {
                    // Prolonged silence — finalize so the user can review
                    Task { @MainActor in
                        await self.stopRecording()
                    }
                }
            } else {
                // Sound detected - reset silence timer
                silenceStartTime = nil
            }
        }
    }

    /// Converts buffer to 16 kHz mono for Speech framework; returns nil on failure.
    /// Output buffer capacity must be >= input frame length per AVAudioConverter requirement.
    private nonisolated static func convertTo16kMono(
        _ buffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let outFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate + 1
        )
        let capacity = max(outFrameCount, buffer.frameLength)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        do {
            try converter.convert(to: outBuffer, from: buffer)
            return outBuffer
        } catch {
            return nil
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> AuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    let auth: AuthorizationStatus
                    switch status {
                    case .notDetermined: auth = .notDetermined
                    case .denied: auth = .denied
                    case .restricted: auth = .denied
                    case .authorized: auth = .authorized
                    @unknown default: auth = .denied
                    }
                    self?.authorizationStatus = auth
                    continuation.resume(returning: auth)
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func checkAvailability() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            throw SpeechError.notAvailable
        }
        if !recognizer.supportsOnDeviceRecognition {
            throw SpeechError.onDeviceUnavailable
        }
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        _ error: Error?,
        generation: UInt64
    ) {
        guard generation == sessionGeneration, !ignoreRecognitionResults else { return }

        if let error = error {
            let nsError = error as NSError
            // Cancellation is expected on the cancel path — not a user-facing failure.
            if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 {
                return
            }
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            // Ignore benign "no speech detected" style failures if we already have text.
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("no speech"),
               !bestAvailableTranscript.isEmpty {
                isProcessing = false
                return
            }
            errorMessage = message
            ignoreRecognitionResults = true
            teardownEngine(cancelTask: true, clearOwnership: false)
            isProcessing = false
            isRecording = false
            return
        }

        guard let result = result else { return }
        let best = result.bestTranscription.formattedString

        if result.isFinal {
            finalizationTimeoutTask?.cancel()
            finalizationTimeoutTask = nil
            if !best.isEmpty {
                transcribedText = best
            } else if transcribedText.isEmpty, !partialTranscribedText.isEmpty {
                // Final arrived empty but we had a usable hypothesis — keep it.
                transcribedText = partialTranscribedText
            }
            partialTranscribedText = ""
            isProcessing = false
            recognitionTask = nil
            recognitionRequest = nil
        } else if !best.isEmpty {
            partialTranscribedText = best
        }
    }

    /// Runs on a background thread to avoid blocking the main thread (watchdog / SIGKILL).
    private nonisolated static func performEngineSetup(
        recognizer: SFSpeechRecognizer,
        onResult: @escaping (SFSpeechRecognitionResult?, Error?) -> Void,
        onLevel: @escaping (Float) -> Void
    ) throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask) {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [AVAudioSession.CategoryOptions.allowBluetoothHFP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        // Keep audio on the device. Without this, `SFSpeechRecognizer` is free
        // to send audio to Apple's servers for some locales — an undisclosed
        // off-device path for the most sensitive data the app touches, which
        // contradicts both the privacy policy and the REQ-POS-001 positioning
        // claim that CI already lints for (Guideline 5.1.2(i)).
        //
        // The cost is locale coverage: where on-device recognition is
        // unavailable, transcription degrades rather than silently uploading.
        // That trade is the honest one, and it is the interim named in
        // docs/app-store/01 §5.1.2 — spec 018 R1's `SpeechAnalyzer` migration is
        // the real fix and supersedes this line.
        // Set unconditionally. Gating this on `supportsOnDeviceRecognition`
        // would mean that exactly when on-device recognition is unavailable the
        // audio gets uploaded instead — the failure we are trying to prevent.
        // Better to fail the recognition request and say so.
        request.requiresOnDeviceRecognition = true
        if !recognizer.supportsOnDeviceRecognition {
            AppLogger.log(
                "⚠️ [SpeechService] On-device recognition unavailable for \(recognizer.locale.identifier); " +
                "transcription will fail rather than send audio off device"
            )
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let speechFormat: AVAudioFormat?
        let converter: AVAudioConverter?
        if inputFormat.sampleRate == 16000 && inputFormat.channelCount == 1 {
            speechFormat = nil
            converter = nil
        } else {
            speechFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
            converter = speechFormat.flatMap { AVAudioConverter(from: inputFormat, to: $0) }
        }

        let task = recognizer.recognitionTask(with: request) { result, error in
            onResult(result, error)
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let toAppend: AVAudioPCMBuffer
            if let conv = converter, let outFmt = speechFormat,
               let converted = Self.convertTo16kMono(buffer, inputFormat: inputFormat, converter: conv, outputFormat: outFmt) {
                toAppend = converted
            } else {
                toAppend = buffer
            }
            request.append(toAppend)
            onLevel(Self.computeRMS(from: buffer))
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            task.cancel()
            throw error
        }
        return (engine, request, task)
    }

    /// Runs on a background thread to avoid blocking the main thread on the
    /// AVAudioSession HAL (watchdog / hang). Symmetric with `performEngineSetup`:
    /// `setActive(false)` and `engine.stop()` can each block for hundreds of ms
    /// while audio routes are torn down, so they must not run on the main actor.
    private nonisolated static func performEngineTeardown(
        engine: AVAudioEngine?,
        request: SFSpeechAudioBufferRecognitionRequest?
    ) {
        // Preserve the original ordering: end audio input, remove the tap while
        // the engine is still valid, stop the engine, then release the session.
        request?.endAudio()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recording

    /// Starts a recording session owned by the specified view.
    /// - Parameter ownerId: Unique identifier for the view starting the recording (e.g., "AddEntryView", "ChatInputField")
    func startRecording(ownerId: String) async throws {
        // Tear down any leftover session before arming a new one.
        teardownEngine(cancelTask: true, clearOwnership: true)

        errorMessage = nil
        transcribedText = ""
        partialTranscribedText = ""
        activeSessionOwner = ownerId
        silenceStartTime = nil
        ignoreRecognitionResults = false
        sessionGeneration &+= 1
        let generation = sessionGeneration

        // 1. Speech authorization
        let speechAuth = await requestAuthorization()
        if speechAuth != .authorized {
            authorizationStatus = speechAuth
            errorMessage = SpeechError.permissionDenied.errorDescription
            activeSessionOwner = nil
            throw SpeechError.permissionDenied
        }

        // 2. Microphone permission
        let micGranted = await requestMicrophonePermission()
        if !micGranted {
            errorMessage = SpeechError.permissionDenied.errorDescription
            activeSessionOwner = nil
            throw SpeechError.permissionDenied
        }

        // 3. Recognizer available + on-device support
        do {
            try checkAvailability()
        } catch {
            errorMessage = (error as? SpeechError)?.errorDescription ?? error.localizedDescription
            activeSessionOwner = nil
            throw error
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            errorMessage = SpeechError.notAvailable.errorDescription
            activeSessionOwner = nil
            throw SpeechError.notAvailable
        }

        // 4–7. Run audio session + engine setup off the main thread to avoid watchdog SIGKILL
        let onResult: (SFSpeechRecognitionResult?, Error?) -> Void = { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error, generation: generation)
            }
        }
        let onLevel: (Float) -> Void = { [weak self] rms in
            Task { @MainActor in
                self?.updateAudioLevel(rms)
            }
        }

        let setupResult: Result<(AVAudioEngine, SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask), Error>
        do {
            let triple = try await Task.detached(priority: .userInitiated) {
                try Self.performEngineSetup(recognizer: recognizer, onResult: onResult, onLevel: onLevel)
            }.value
            setupResult = .success(triple)
        } catch {
            setupResult = .failure(error)
        }

        switch setupResult {
        case .failure(let error):
            let msg = (error as NSError).localizedDescription
            errorMessage = (SpeechError.engineStartFailed(msg)).errorDescription
            isProcessing = false
            activeSessionOwner = nil
            throw SpeechError.engineStartFailed(msg)
        case .success((let engine, let request, let task)):
            audioEngine = engine
            recognitionRequest = request
            recognitionTask = task
            isProcessing = true
            isRecording = true

            let startTime = Date()
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, self.isRecording else { return }
                    self.currentDuration = Date().timeIntervalSince(startTime)
                }
            }
            RunLoop.main.add(durationTimer!, forMode: .common)
        }
    }

    /// Stops capture and waits for a final transcript (task left running until final/timeout).
    func stopRecording() async {
        guard isRecording || audioEngine != nil || recognitionRequest != nil else {
            isRecording = false
            return
        }

        // Main-actor UI/state resets — immediate, non-blocking so the mic UI
        // flips the moment the user stops, before the hardware finishes tearing down.
        durationTimer?.invalidate()
        durationTimer = nil
        currentDuration = 0
        silenceStartTime = nil
        audioLevel = 0
        smoothedLevel = 0
        isRecording = false

        // Hand the hardware objects to a background thread and clear our refs on
        // the main actor. The closure retains them until teardown completes, so
        // nulling here is safe.
        let engine = audioEngine
        let request = recognitionRequest
        audioEngine = nil
        recognitionRequest = nil
        // Note: recognitionTask is intentionally NOT cancelled — it finishes for
        // the final transcription and is cleared in handleRecognitionResult when isFinal.

        // Run the blocking AVAudioSession/engine teardown off the main actor
        // (mirror of the setup path; AVAudioSession hang fix — endAudio, engine
        // stop, and setActive(false) all leave the main thread). Awaited so
        // `setActive(false)` is strictly ordered before any immediate restart's
        // `setActive(true)`, avoiding an activate/deactivate race on the shared session.
        await Task.detached(priority: .userInitiated) {
            Self.performEngineTeardown(engine: engine, request: request)
        }.value

        // Keep isProcessing true until final (or timeout) so UI can show "finishing…"
        scheduleFinalizationTimeout()
        // Note: activeSessionOwner is intentionally NOT cleared here.
        // It remains set so the owning view can consume the transcribedText.
        // It will be cleared when the next recording starts or on cancel/clear.
    }

    /// Cancels the session immediately. Drops any in-flight final so cancel cannot
    /// race into a late send/insert (the narrate X / mishearing escape hatch).
    func cancelRecording() async {
        ignoreRecognitionResults = true
        sessionGeneration &+= 1
        teardownEngine(cancelTask: true, clearOwnership: true)

        transcribedText = ""
        partialTranscribedText = ""
        errorMessage = nil
        isProcessing = false
        isRecording = false
        currentDuration = 0
        silenceStartTime = nil
        audioLevel = 0
        smoothedLevel = 0
    }

    /// Best available transcript for the current session (final preferred, else live partial).
    var bestAvailableTranscript: String {
        let final = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty { return final }
        return partialTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks if the given owner is the active session owner.
    /// Use this to determine if your view should process the transcription.
    func isOwner(_ ownerId: String) -> Bool {
        activeSessionOwner == ownerId
    }

    /// Clears the transcription and resets ownership after consuming the result.
    func clearTranscription() {
        transcribedText = ""
        partialTranscribedText = ""
        activeSessionOwner = nil
        isProcessing = false
    }

    // MARK: - Teardown helpers

    private func scheduleFinalizationTimeout() {
        finalizationTimeoutTask?.cancel()
        let generation = sessionGeneration
        finalizationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard !Task.isCancelled else { return }
            guard generation == self.sessionGeneration else { return }
            guard self.isProcessing else { return }

            // Promote the last partial so consumers are not left hanging with empty text.
            if self.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !self.partialTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.transcribedText = self.partialTranscribedText
            }
            self.partialTranscribedText = ""
            self.isProcessing = false
            self.recognitionTask = nil
            self.recognitionRequest = nil
            AppLogger.log("⚠️ [SpeechService] Finalization timed out; promoted partial transcript if available")
        }
    }

    private func teardownEngine(cancelTask: Bool, clearOwnership: Bool) {
        durationTimer?.invalidate()
        durationTimer = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil

        if cancelTask {
            recognitionTask?.cancel()
        }

        // Capture the hardware and clear refs on the main actor, then run the
        // blocking endAudio / engine.stop() / setActive(false) off the main thread
        // (AVAudioSession hang fix — those calls can block for hundreds of ms).
        // Fire-and-forget: cancel/error paths don't immediately restart, so there
        // is no activate/deactivate ordering that needs awaiting. The closure
        // retains the objects until teardown completes.
        let engine = audioEngine
        let request = recognitionRequest
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        Task.detached(priority: .userInitiated) {
            Self.performEngineTeardown(engine: engine, request: request)
        }

        audioLevel = 0
        smoothedLevel = 0
        silenceStartTime = nil
        currentDuration = 0

        if clearOwnership {
            activeSessionOwner = nil
        }
    }
}
