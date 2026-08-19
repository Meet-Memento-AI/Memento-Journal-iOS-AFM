# SupertonicTTS — vendored fork

CoreML Supertonic 3 inference, vendored from
[`soniqo/speech-swift`](https://github.com/soniqo/speech-swift) (Apache-2.0).

**Pinned upstream commit:** `f9af2f34d196eacca85d13fe508d8ed71919671f`
**Vendored:** 2026-08-18

## Why vendored rather than a package dependency

Spec `030` R1 forbids shipping any model-download code, and `021` R6 governs
third-party SPM packages. Upstream's `SupertonicTTS` target depends on
`AudioCommon`, which depends on `Hub` from `swift-transformers` —
HuggingFace's hub client. Linking it unmodified would ship a HuggingFace
downloader inside the TTS path, which is precisely what `REQ-TTS-001` exists to
prevent.

Vendoring the six source files plus one 49-line helper avoids that entirely and
keeps the **third-party SPM surface at zero**.

## Divergences from upstream

1. **`fromPretrained()` removed**, along with `import AudioCommon`. It was the
   Hugging Face download path. Removed, not flag-guarded — a flag can be flipped
   by a refactor that does not know what it is flipping (`030` R1).
2. **`init(assets:)` replaces `init(directory:)`.** Upstream resolves every
   asset under one directory. This app bundles its assets, and a
   file-system-synchronized Xcode group **flattens resources to the bundle
   root** — so `voice_styles/F1.json` ships as `F1.json` beside the graphs, and
   no such directory exists at runtime. Explicit URLs decouple the model from
   however Xcode chooses to lay resources out.
3. **`loadVoices` takes explicit style URLs** instead of scanning
   `<dir>/voice_styles`, for the same reason.
4. **`CoreMLComputeUnits.swift` vendored verbatim** from `AudioCommon` — the one
   symbol `SupertonicGraphs` genuinely needed. Its `SPEECH_COREML_COMPUTE_UNITS`
   env override is retained and is useful for forcing `cpuOnly` in CI.

5. **`MLMultiArrayDataType.int8` handled** in `SupertonicGraphs.toFloat32`, and
   the `@unknown default` made loud with an `assertionFailure`. `.int8` was added
   in **iOS 26**, after this code was written upstream, so it fell through to
   `@unknown default: break` and the function returned an **all-zero array** —
   silent audio, no error, no crash. That is the worst failure mode a TTS engine
   has, and it is directly relevant here because we ship an **8-bit palettized**
   `VectorEstimator`. Found via a `switch must be exhaustive` warning in an Xcode
   26.0.1 build log.

Everything else — the tokenizer, the four-graph flow-matching pipeline, tensor
marshalling — is upstream's, unmodified.

## Governance note

A **local** package has no `repositoryURL`, so
`scripts/ci/check_dependency_allowlist.sh` cannot see it — the same blind spot
already recorded for the model weights. This file is the record that it was
reviewed, not an oversight.

## Updating

Re-fetch the six `Sources/SupertonicTTS/*.swift` files and
`Sources/AudioCommon/CoreMLComputeUnits.swift` at the new commit, then re-apply
divergences 1–3. Update the pin above. Treat it as a reviewed act, not a bump.

## Licence

Apache-2.0, upstream `soniqo/speech-swift`. Model weights are separately
licensed (OpenRAIL-M) — see spec `018` R12 and Settings → Acknowledgments.
