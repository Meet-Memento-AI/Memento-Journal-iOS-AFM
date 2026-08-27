//
//  SpeechAnalyzerEngine.swift
//  MeetMemento
//
//  Spec 018 R1: SpeechAnalyzer + SpeechTranscriber + SpeechDetector.
//  No SFSpeechAudioBufferRecognitionRequest / recognitionTask.
//  Speech recognition *permission* still uses the Speech framework's
//  authorization API (typed historically as SFSpeechRecognizer).
//

import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechAnalyzerEngine {
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var onLevel: ((Float) -> Void)?
    private var onSpeechDetected: ((Bool) -> Void)?
    private var onUpdate: ((TranscriptionUpdate) -> Void)?
    /// True when the analyzer is allocated but the mic tap is down (TTS half-duplex).
    private(set) var isCapturePaused = false

    var lastAssetState: TranscriptionAssetState = .missing

    func assetState(for locale: Locale, style: TranscriptionStyle = .dictation) async -> TranscriptionAssetState {
        let transcriber = makeTranscriber(locale: locale, style: style)
        let status = await AssetInventory.status(forModules: [transcriber])
        let mapped: TranscriptionAssetState
        switch status {
        case .installed: mapped = .installed
        case .downloading: mapped = .downloading
        case .supported: mapped = .missing
        case .unsupported: mapped = .unsupported
        @unknown default: mapped = .missing
        }
        lastAssetState = mapped
        return mapped
    }

    func ensureAssets(for locale: Locale, style: TranscriptionStyle = .dictation) async {
        let transcriber = makeTranscriber(locale: locale, style: style)
        if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            lastAssetState = .downloading
            try? await request.downloadAndInstall()
            lastAssetState = .installed
        }
    }

    func start(
        locale: Locale,
        style: TranscriptionStyle = .dictation,
        onUpdate: @escaping (TranscriptionUpdate) -> Void,
        onLevel: @escaping (Float) -> Void,
        onSpeechDetected: @escaping (Bool) -> Void
    ) async throws {
        await cancel()
        isCapturePaused = false
        self.onLevel = onLevel
        self.onSpeechDetected = onSpeechDetected
        self.onUpdate = onUpdate

        let transcriber = makeTranscriber(locale: locale, style: style)
        // SpeechDetector is the 034 VAD type. On iOS 26 SDK 3500.107 it does
        // not publicly conform to SpeechModule, so it cannot join `modules:`.
        // Keep a live instance so the type stays in the capture path; barge-in
        // currently uses RMS from the mic tap.
        _ = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        self.transcriber = transcriber
        self.analyzer = analyzer

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        analyzerFormat = format

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { break }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self?.onUpdate?(.finalized(text))
                    } else {
                        self?.onUpdate?(.volatile(text))
                    }
                }
            } catch {
                AppLogger.log("[SpeechAnalyzer] transcriber results: \(error.localizedDescription)")
            }
            _ = self
        }

        analyzerTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                AppLogger.log("[SpeechAnalyzer] start: \(error.localizedDescription)")
            }
        }

        try startMic(format: format, onLevel: onLevel, onSpeechDetected: onSpeechDetected)
    }

    /// Mic tap off, analyzer kept. Pause is allocation, not a live tap —
    /// TTS takes `.playback` while the transcriber stays warm for the next listen.
    func pauseCapture() {
        guard analyzer != nil else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        isCapturePaused = true
    }

    /// Re-arm the mic into the still-running analyzer. Returns false when
    /// there is nothing paused — caller should cold-start.
    @discardableResult
    func resumeCapture(
        onUpdate: @escaping (TranscriptionUpdate) -> Void,
        onLevel: @escaping (Float) -> Void,
        onSpeechDetected: @escaping (Bool) -> Void
    ) throws -> Bool {
        guard isCapturePaused, analyzer != nil, inputContinuation != nil else {
            return false
        }
        self.onUpdate = onUpdate
        self.onLevel = onLevel
        self.onSpeechDetected = onSpeechDetected
        try startMic(format: analyzerFormat, onLevel: onLevel, onSpeechDetected: onSpeechDetected)
        isCapturePaused = false
        return true
    }

    private func makeTranscriber(locale: Locale, style: TranscriptionStyle) -> SpeechTranscriber {
        switch style {
        case .dictation:
            return SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
        case .conversation:
            // `.transcription` is the punctuation-oriented preset. Keep
            // volatile results so the live bubble still streams.
            let preset = SpeechTranscriber.Preset.transcription
            return SpeechTranscriber(
                locale: locale,
                transcriptionOptions: preset.transcriptionOptions.union([.etiquetteReplacements]),
                reportingOptions: preset.reportingOptions.union([.volatileResults]),
                attributeOptions: preset.attributeOptions.union([
                    .audioTimeRange, .transcriptionConfidence
                ])
            )
        }
    }

    func finish() async {
        inputContinuation?.finish()
        inputContinuation = nil
        stopMic()
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        detectorTask?.cancel()
        analyzerTask?.cancel()
        resultsTask = nil
        detectorTask = nil
        analyzerTask = nil
        analyzer = nil
        transcriber = nil
        isCapturePaused = false
        onUpdate = nil
        onSpeechDetected = nil
        onLevel = nil
    }

    func cancel() async {
        inputContinuation?.finish()
        inputContinuation = nil
        stopMic()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        resultsTask?.cancel()
        detectorTask?.cancel()
        analyzerTask?.cancel()
        resultsTask = nil
        detectorTask = nil
        analyzerTask = nil
        analyzer = nil
        transcriber = nil
        isCapturePaused = false
        onUpdate = nil
        onSpeechDetected = nil
        onLevel = nil
    }

    func pause() {
        audioEngine?.pause()
    }

    func resume() throws {
        try audioEngine?.start()
    }

    private func startMic(
        format: AVAudioFormat?,
        onLevel: @escaping (Float) -> Void,
        onSpeechDetected: @escaping (Bool) -> Void
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        if let format {
            converter = AVAudioConverter(from: micFormat, to: format)
        } else {
            converter = nil
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let rms = SpeechService.computeRMS(from: buffer)
            onLevel(rms)
            onSpeechDetected(rms > 0.03)
            let toSend: AVAudioPCMBuffer
            if let converter = self.converter, let format = self.analyzerFormat,
               let converted = Self.convert(buffer, with: converter, to: format) {
                toSend = converted
            } else {
                toSend = buffer
            }
            self.inputContinuation?.yield(AnalyzerInput(buffer: toSend))
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func stopMic() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: out, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if conversionError != nil { return nil }
        return out
    }
}
