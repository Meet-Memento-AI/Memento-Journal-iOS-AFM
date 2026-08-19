//
//  SupertonicEngine.swift
//  MeetMemento
//
//  The neural voice engine (spec 031 R1/R2). An actor, one instance app-wide.
//
//  NOTE — no `import CoreML` here, deliberately. CONSTITUTION rule 11 requires
//  exactly one Swift module to import CoreML; that module is the vendored
//  `SupertonicTTS` package. This file talks to it through Swift types only, so
//  the app target imports CoreML nowhere at all. Keep it that way: if you find
//  yourself needing `MLComputeUnits` here, add the knob to the package instead.
//

import AVFoundation
import Foundation
import SupertonicTTS

/// Zone: .z0Device (spec 014 R1). Local computation over local text — no
/// network at synthesis, load, or voice-selection time (REQ-TTS-001), which is
/// structural rather than enforced: the model is in the bundle and the vendored
/// package has no networking code in it at all.
actor SupertonicEngine {

    static let shared = SupertonicEngine()

    enum EngineError: LocalizedError {
        case assetsMissing([String])
        case notWarm

        var errorDescription: String? {
            switch self {
            case .assetsMissing(let names):
                return "Voice assets missing from the bundle: \(names.joined(separator: ", "))"
            case .notWarm:
                return "Voice engine is not loaded."
            }
        }
    }

    private var model: SupertonicTTSModel?

    /// True once the graphs are loaded and a synthesis can run without paying
    /// load cost. Cheap to query; callers use it to decide whether to warm.
    var isWarm: Bool { model != nil }

    private init() {}

    // MARK: - Lifecycle

    /// Loads the four graphs and the four style vectors. Idempotent — a second
    /// call while warm returns immediately (spec 031 R3).
    ///
    /// Invoked on **user-intent signals** (a voice surface appearing), never
    /// from a play action: the shipped `.mlmodelc` needs no compilation, but ANE
    /// specialization still happens on first load, and that cost must not land
    /// on the first sentence a user asks to hear.
    func prepare() throws {
        guard model == nil else { return }

        guard VoicePack.isComplete,
              let modelsDirectory = VoicePack.modelsDirectory,
              let unicodeIndexer = VoicePack.unicodeIndexer
        else {
            throw EngineError.assetsMissing(VoicePack.missingAssets())
        }

        let assets = SupertonicTTSModel.Assets(
            modelsDirectory: modelsDirectory,
            unicodeIndexer: unicodeIndexer,
            styles: VoicePack.styleURLs()
        )

        // Exclude the GPU. The Vocoder's dynamic latent axis (RangeDims 4...512)
        // cannot run on MPSGraph — it fails with "invalid axis: -1258641855" and
        // "shape for TensorData is not static" on device. `.all` lets CoreML pick
        // that backend, prediction throws, and the caller falls back to the system
        // voice — which is exactly the "why am I hearing Samantha" bug.
        // See SupertonicCompute and V29/DEC-008.
        let loaded = try SupertonicTTSModel(assets: assets, compute: .cpuAndNeuralEngine)

        // Upstream inserts 0.3 s of silence between the chunks its tokenizer
        // splits text into (the model's text front end is fixed at 128 tokens,
        // so long text is always chunked). Spec 032 R2 requires chunk joins to
        // be gapless, so this is zeroed: any pacing is the app's decision, made
        // where the app can see the whole utterance, not the model's default.
        loaded.chunkSilenceSeconds = 0

        model = loaded
    }

    /// Releases the graphs. Spec 031 R6's memory-pressure valve; re-warms lazily.
    func releaseForMemoryPressure() {
        model = nil
    }

    // MARK: - Synthesis

    /// Renders `text` in the given style to mono Float32 PCM.
    ///
    /// Warms on demand if cold, so a caller that forgot to `prepare()` gets
    /// correct audio rather than an error — it simply pays the load cost.
    ///
    /// `speed` is the model's own pacing control, not a playback-rate trick: it
    /// divides the DurationPredictor's output, so the flow-matching stage renders
    /// a genuinely faster or slower reading. Resampling the finished buffer would
    /// shift pitch; this does not. Callers pass `SpeechRatePreset.neuralSpeed`.
    /// The default matches the model's own, for callers with no rate preference.
    func synthesize(text: String,
                    styleID: String,
                    language: String = "en",
                    speed: Float = 1.05) throws -> AVAudioPCMBuffer {
        if model == nil { try prepare() }
        guard let model else { throw EngineError.notWarm }

        let samples = try model.synthesize(text: text,
                                           voice: styleID,
                                           language: language,
                                           options: SupertonicOptions(speed: speed))
        return try Self.buffer(from: samples, sampleRate: Double(model.sampleRate))
    }

    /// Style ids the loaded model can actually render. Should match
    /// `VoiceCatalog.all`; a mismatch means the vendored assets and the catalog
    /// have drifted apart.
    func availableStyleIDs() throws -> [String] {
        if model == nil { try prepare() }
        return model?.availableVoices ?? []
    }

    // MARK: - PCM

    private static func buffer(from samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(max(samples.count, 1)))
        else {
            throw EngineError.notWarm
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
