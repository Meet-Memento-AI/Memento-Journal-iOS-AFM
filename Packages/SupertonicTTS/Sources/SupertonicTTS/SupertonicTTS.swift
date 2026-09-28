#if canImport(CoreML)
import CoreML
import Foundation

/// SupertonicTTS-3 on Apple via CoreML — 99M non-autoregressive flow-matching multilingual TTS
/// (44.1 kHz, 31 languages, **G2P-free**). Mirrors the C++ `LiteRTSupertonicTts` but, because the
/// CoreML graphs carry a `RangeDim` latent axis, the host runs at the **true** latent length per
/// utterance — no fixed-window truncation.
///
///     let tts = try SupertonicTTSModel(assets: .init(...))
///     let pcm = try tts.synthesize(text: "Hello there", voice: "F1", language: "en")  // [Float] @ 44.1 kHz
///
/// **VENDORED FORK — see VENDORING.md.** Divergences from upstream:
///   1. `fromPretrained()` and the Hugging Face download path are **removed**
///      (spec 030 R1: the app ships no model-download code at all).
///   2. `init(assets:)` takes explicit file URLs instead of a directory, because
///      the app bundles its assets and Xcode flattens them to the bundle root —
///      there is no `voice_styles/` directory at runtime.
public final class SupertonicTTSModel: @unchecked Sendable {

    /// Explicit locations for the bundled assets.
    ///
    /// Upstream resolves everything under one directory. The app cannot: a
    /// file-system-synchronized Xcode group flattens resources into the bundle
    /// root, so `voice_styles/F1.json` ships as `F1.json` beside the graphs.
    /// Passing URLs keeps this decoupled from however Xcode chooses to lay
    /// resources out.
    public struct Assets: Sendable {
        /// Directory containing `<Name>.mlmodelc` for the four graphs.
        public let modelsDirectory: URL
        /// `unicode_indexer.json`.
        public let unicodeIndexer: URL
        /// Style id → style-vector JSON, e.g. `["F1": …/F1.json]`.
        public let styles: [String: URL]

        public init(modelsDirectory: URL, unicodeIndexer: URL, styles: [String: URL]) {
            self.modelsDirectory = modelsDirectory
            self.unicodeIndexer = unicodeIndexer
            self.styles = styles
        }
    }

    struct VoiceStyle { let ttl: [Float]; let dp: [Float] }   // [1,50,256], [1,8,16]

    private let config: SupertonicConfig
    private let tokenizer: SupertonicTokenizer
    private let graphs: SupertonicGraphs
    private let voices: [String: VoiceStyle]
    public let defaultVoice: String

    /// Voice ids available (e.g. "F1"…"F5", "M1"…"M5").
    public var availableVoices: [String] { voices.keys.sorted() }

    /// Inter-chunk silence in seconds.
    public var chunkSilenceSeconds: Double = 0.3

    /// Loads the four graphs and the supplied style vectors. Synchronous and
    /// offline by construction — there is nothing to fetch.
    public init(assets: Assets,
                compute: SupertonicCompute = .cpuAndNeuralEngine,
                config: SupertonicConfig = .default) throws {
        let computeUnits = compute.mlComputeUnits
        self.config = config
        self.tokenizer = try SupertonicTokenizer.load(from: assets.unicodeIndexer)
        self.graphs = try SupertonicGraphs(dir: assets.modelsDirectory,
                                           cacheDir: assets.modelsDirectory,
                                           computeUnits: computeUnits)
        self.voices = try Self.loadVoices(styleURLs: assets.styles, config: config)
        guard !voices.isEmpty else {
            throw SupertonicError.badAsset("no usable voice styles in \(assets.styles.keys.sorted())")
        }
        self.defaultVoice = voices["F1"] != nil ? "F1" : voices.keys.sorted().first!
    }

    // MARK: - synthesis

    /// Synthesize `text` in ISO `language` with `voice` → mono Float32 PCM at `sampleRate`.
    public func synthesize(text: String,
                           voice: String? = nil,
                           language: String = "en",
                           options: SupertonicOptions = .default) throws -> [Float] {
        let voiceId = voice ?? defaultVoice
        guard let style = voices[voiceId] else { throw SupertonicError.voiceNotFound(voiceId) }
        guard tokenizer.supports(language) else { throw SupertonicError.unsupportedLanguage(language) }

        let chunks = tokenizer.chunk(text, lang: language, textLength: config.textLength)
        let baseSeed = options.seed != 0 ? options.seed : UInt64.random(in: 1...UInt64.max)
        let silence = Int(chunkSilenceSeconds * Double(config.sampleRate))

        var out: [Float] = []
        for (ci, chunk) in chunks.enumerated() {
            // Decorrelate the latent noise per chunk.
            let seed = baseSeed &+ (0x9E3779B97F4A7C15 &* UInt64(ci + 1))
            let pcm = try synthChunk(chunk, lang: language, voice: style, options: options, seed: seed)
            if ci > 0, silence > 0 { out.append(contentsOf: [Float](repeating: 0, count: silence)) }
            out.append(contentsOf: pcm)
        }
        return out
    }

    private func synthChunk(_ chunk: String, lang: String, voice: VoiceStyle,
                            options: SupertonicOptions, seed: UInt64) throws -> [Float] {
        let T = config.textLength, C = config.latentChannels, chunkSize = config.chunkSamples
        let tok = try tokenizer.process(chunk, lang: lang, textLength: T)

        let textIds = try SupertonicBridge.int32(tok.ids, shape: [1, T])
        let textMask = try SupertonicBridge.fp32(tok.mask, shape: [1, 1, T])
        let styleTtl = try SupertonicBridge.fp32(voice.ttl, shape: [1, 50, 256])
        let styleDp = try SupertonicBridge.fp32(voice.dp, shape: [1, 8, 16])

        // 1) duration → seconds, /speed.
        var dur = try graphs.predictDuration(textIds: textIds, styleDp: styleDp, textMask: textMask)
        dur /= options.speed
        guard dur > 0, dur.isFinite else { return [] }

        // 2) text embedding (reused across the ODE steps).
        let textEmb = try graphs.encodeText(textIds: textIds, styleTtl: styleTtl, textMask: textMask)

        // 3) latent geometry — TRUE length (RangeDim), floored at the vector_estimator minimum.
        let wavLen = Int(Double(dur) * Double(config.sampleRate))        // truncate, matches infer.py
        let lTrue = (wavLen + chunkSize - 1) / chunkSize
        let L = max(lTrue, config.latentMin)
        let lFill = min(max(lTrue, 1), L)

        var latentMask = [Float](repeating: 0, count: L)
        for t in 0..<lFill { latentMask[t] = 1 }

        var rng = GaussianRNG(seed: seed)
        var xt = [Float](repeating: 0, count: C * L)
        for c in 0..<C {
            let base = c * L
            for t in 0..<L { xt[base + t] = rng.nextGaussian() * latentMask[t] }
        }

        let latentMaskArr = try SupertonicBridge.fp32(latentMask, shape: [1, 1, L])
        let totalStepArr = try SupertonicBridge.fp32([Float(options.totalStep)], shape: [1])

        // 4) flow-matching ODE — feed xt forward.
        for step in 0..<options.totalStep {
            let noisy = try SupertonicBridge.fp32(xt, shape: [1, C, L])
            let cur = try SupertonicBridge.fp32([Float(step)], shape: [1])
            let denoised = try graphs.vectorStep(
                noisy: noisy, textEmb: textEmb, styleTtl: styleTtl,
                latentMask: latentMaskArr, textMask: textMask, currentStep: cur, totalStep: totalStepArr)
            xt = SupertonicBridge.toFloat32(denoised)
        }

        // 5) vocode + trim to floor(SR*dur).
        let latent = try SupertonicBridge.fp32(xt, shape: [1, C, L])
        let wav = try graphs.vocode(latent: latent)
        var n = Int(Double(config.sampleRate) * Double(dur))
        n = min(n, chunkSize * lFill)
        n = min(n, wav.count)
        return Array(wav.prefix(n))
    }

    // MARK: - voices

    private static func flattenFloats(_ obj: Any) -> [Float] {
        if let arr = obj as? [Any] { return arr.flatMap { flattenFloats($0) } }
        if let n = obj as? NSNumber { return [n.floatValue] }
        return []
    }

    /// Loads style vectors from explicit URLs (fork divergence — upstream scanned
    /// `<dir>/voice_styles`, which the flattened app bundle does not have).
    private static func loadVoices(styleURLs: [String: URL],
                                   config: SupertonicConfig) throws -> [String: VoiceStyle] {
        var voices: [String: VoiceStyle] = [:]
        for (id, url) in styleURLs {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)),
                  let json = obj as? [String: Any],
                  let ttlNode = json["style_ttl"] as? [String: Any], let ttlData = ttlNode["data"],
                  let dpNode = json["style_dp"] as? [String: Any], let dpData = dpNode["data"]
            else { continue }
            let ttl = flattenFloats(ttlData), dp = flattenFloats(dpData)
            guard ttl.count == config.styleTtlCount, dp.count == config.styleDpCount else { continue }
            voices[id] = VoiceStyle(ttl: ttl, dp: dp)
        }
        return voices
    }
}

/// Deterministic Gaussian sampler (SplitMix64 + Box–Muller). Runtime noise is stochastic anyway
/// (flow-matching: "trajectory divergence, not degradation"); a fixed seed makes it reproducible.
struct GaussianRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    private mutating func nextU64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    private mutating func nextUniform() -> Float {
        Float((nextU64() >> 40) &+ 1) / Float(1 << 24)   // (0,1]
    }
    mutating func nextGaussian() -> Float {
        let u1 = nextUniform(), u2 = nextUniform()
        return sqrtf(-2 * logf(u1)) * cosf(2 * .pi * u2)
    }
}
#endif
