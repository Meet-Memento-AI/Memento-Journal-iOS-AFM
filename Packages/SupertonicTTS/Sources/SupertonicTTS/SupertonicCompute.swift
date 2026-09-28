#if canImport(CoreML)
import CoreML

/// **VENDORED FORK divergence 6 — see VENDORING.md.**
///
/// A CoreML-free way for the host app to choose a backend. `MLComputeUnits` is a
/// CoreML type, and the app target is forbidden from importing CoreML
/// (CONSTITUTION rule 11 — exactly one module may). This enum lets the app say
/// what it wants without naming CoreML at all.
///
/// **Why this exists at all**, concretely: the Vocoder graph has a dynamic latent
/// axis (`latent [1, 144, ?]`, RangeDims 4...512). Dispatched to the **GPU via
/// MPSGraph** on an iPhone 16 Pro it fails outright —
///
///     Vocoder.mlmodelc/model.mil:242:12: error: invalid axis: -1258641855
///     'mps.expand_dims' op invalid axis: ... rank = 4
///     MPSRuntime.mm:1515: error 'shape for TensorData is not static'
///
/// MPS requires static shapes and reads garbage for the dynamic one. So `.all`
/// is unsafe here: it lets CoreML pick the one backend that cannot run this
/// graph. Exclude the GPU.
public enum SupertonicCompute: String, Sendable {
    /// CPU + Neural Engine, no GPU. The default, and the reason this type exists.
    case cpuAndNeuralEngine
    /// CPU only. Slowest, always correct — the simulator path.
    case cpuOnly
    /// Let CoreML choose, including GPU. **Known to fail on the Vocoder.**
    case all

    var mlComputeUnits: MLComputeUnits {
        switch self {
        case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
        case .cpuOnly: return .cpuOnly
        case .all: return .all
        }
    }
}
#endif
