#if canImport(CoreML)
import Foundation

/// **VENDORED FORK divergence 4 — see VENDORING.md.**
///
/// Upstream conformed this type to `AudioCommon.SpeechGenerationModel` so it
/// would drop into the same CLI/server pipelines as their other TTS models. We
/// import none of that, so the conformance is dropped and only the one piece the
/// app genuinely needs is kept: the output sample rate, which the playback layer
/// needs to build an `AVAudioFormat`.
public extension SupertonicTTSModel {
    /// Output sample rate. Supertonic 3 renders at 44.1 kHz.
    var sampleRate: Int { 44_100 }
}
#endif
