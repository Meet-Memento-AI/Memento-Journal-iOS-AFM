---
id: 030
title: Neural TTS Model Assets — Bundled In-App
tier: P1
status: not-started
effort: 2 sessions
depends_on: [018]
findings: [bundled-not-downloaded-dec-012, synchronized-group-flattens-to-bundle-root, huggingface-autodownload-in-tts-path, upstream-not-archived-premise-corrected, no-acknowledgments-screen-ofl-unattributed, model-weights-invisible-to-dependency-gate, asset-size-escalation-threshold]
source_refs: [REQ-TTS-001, REQ-TTS-002, REQ-TTS-003, REQ-TTS-006, REQ-TTS-009, REQ-MON-005, DEC-010, DEC-012]
tech_refs: [technology/13-neural-tts-coreml.md, technology/06-speech-and-audio.md]
---

# 030 — Neural TTS Model Assets and Vendoring

**Traceability:** first spec of the neural-voice family (030–036) and the one
that **mints the `REQ-TTS-` series** in
`specs/reference/memento-2.0-architecture-spec.md` §8.6. Sits on
`specs/018-capture-and-voice-output.md` R7 (rewritten 2026-08-18 — synthesis is
on-device, not single-vendor) and R12 (text-front-end licensing gate). Owns
`DEC-010` and V31. Governed by `specs/021-monetization-and-store-compliance.md`
R6 for the dependency it adds.

## Why

The engine is worthless if its weights arrive by the wrong road. The stock SDK
downloads model assets from Hugging Face on first run — a network call inside the
TTS path, pointed at a third-party repository. The first breaks the privacy rule
this family exists to satisfy (`REQ-TTS-001`); the second makes the app's core
voice feature depend on someone else's decision to keep a bucket alive.
*(Corrected 2026-08-18: this spec was drafted believing the upstream was
**archived**. It is not — `supertone-inc/supertonic` was last pushed 2026-07-24
and `soniqo/speech-swift` on 2026-08-17. The availability argument is weaker than
first written, but it is not void: a live third party can still move, rename, or
rate-limit a bucket, and none of that should be able to silence the app.)* Neither is survivable, and both are fixed in the same
place: **we** decide where the weights come from, **we** verify them before they
load, and the download code that ships is ours rather than an upstream's. As of
there is no channel at all any more (R2) — the point was never that Memento runs
a server, it was that no third party gets to decide whether the app can speak,
and a model in the binary settles that permanently.

> **Superseded in the best way, 2026-08-18 (`DEC-012`).** Everything above
> described a *download*. There is no longer one: the model is vendored into the
> repository and ships **inside the app binary**. The privacy argument that took
> two designs and a proxy-capture plan to make defensible is now structural — a
> TTS path with no network code in it cannot leak, and that is easier to verify
> than any amount of egress testing.
>
> What the change costs is app size, which R7 answers, and what it buys —
> beyond simplicity — is that the voice works on first launch, in airplane mode,
> forever, with no state in between.

This spec is still first, because everything downstream assumes the model is
present at a known location — and because the two things most likely to sink the
feature late (app size and a licence nobody read) are decided here.

## Technology References

- `specs/reference/technology/13-neural-tts-coreml.md` §1 (what the model is,
  🔴), §2–§3 (CoreML loading, compute placement, verified shapes), §7 (licensing,
  🟡). §6/§6a (Background Assets, Apple-hosted packs) are **superseded by
  bundling** and retained for provenance only.
- `specs/reference/technology/06-speech-and-audio.md` §B1–B2 (amended
  2026-08-18) — the `AVSpeechSynthesizer` fallback this spec must keep alive.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | ~~No on-device ML asset machinery exists~~ **PARTLY CLOSED 2026-08-18** — the model is vendored and bundled; no engine code exists yet | `MeetMemento/Resources/Voices/` present (148 MB, four `.mlmodelc` + four style vectors); `grep -rn 'import CoreML' MeetMemento/` still **zero hits** — spec 031 owns that | Medium — assets done, engine greenfield |
| 2 | The only precedent for app-managed on-device model data is an embedding cache, not a downloaded model | `MeetMemento/Services/Intelligence/EmbeddingService.swift` — `NLEmbedding` + disk cache under Application Support, `.completeFileProtection` | Medium — reusable pattern, wrong scale |
| 3 | The stock SDK auto-downloads weights from Hugging Face on first run, inside the synthesis path | `technology/13` §1, §6 | **Critical** — violates `REQ-TTS-001` |
| 4 | **No Acknowledgments screen exists**, and three OFL-licensed font families already ship unattributed | `MeetMemento/Views/Settings/AboutSettingsView.swift` has App Information / Support / Legal / Share only; `MeetMemento/Resources/Fonts/` contains Figtree, Lora, Manrope + an `OFL.txt` referenced by **no** Swift file (`grep -rn "OFL\|Acknowledg" MeetMemento --include="*.swift"` → no attribution surface) | High — a live licence gap, independent of TTS |
| 5 | Model weights pass the dependency gate invisibly — it reads SPM package identities only | `scripts/ci/check_dependency_allowlist.sh` parses `repositoryURL = "…"` out of `project.pbxproj`; a 200 MB model is not a `repositoryURL` | Medium — governance blind spot |
| 6 | ~~The dependency gate is still report-only~~ **RESOLVED 2026-08-18** — gate is enforcing and the resolved third-party SPM set is empty | `ALLOWLIST_ENFORCE=1 scripts/ci/check_dependency_allowlist.sh` exits 0; `svgkit/svgkit` removed (linked to no target, imported nowhere) along with its `cocoalumberjack` + `swift-log` pins; `Package.resolved` deleted; build and unit suite green | Closed — see R7 |
| 7 | The fallback this spec must preserve is real and shipping | `MeetMemento/Services/VoicePlaybackService.swift:709` `bestVoiceIdentifier(from:currentLanguage:)`; `:243/:271/:297` the utterance-session primitives every caller uses | — (asset to protect) |

## Requirements

**Traceability:** R1 → `REQ-TTS-001`; R2, R3 → `REQ-TTS-002`; R4 → `REQ-TTS-006`
(catalog data, consumed by 033); R5 → `REQ-TTS-003`; R6 → `REQ-TTS-009` /
`DEC-010` / 018 R12; R7 → `REQ-MON-005` and this spec's size escalation; R8 has
no `REQ-` ID — verification-queue ownership.

**Zone declaration:** everything in this spec is `.z0Device` per spec 014 R1.
Asset delivery moves **our** files from **our** storage to the device once; it
carries no user content in either direction, and it happens outside the synthesis
path entirely. That distinction is the whole design, and R1 is what makes it
checkable rather than merely claimed.

### R1. Zero egress from the TTS path — by construction, not by policy (`REQ-TTS-001`)

The app MUST NOT contain any code path that downloads model assets from Hugging
Face or from any upstream-controlled endpoint. Where the vendored integration
surface ships auto-download behavior, it is **stripped or forked out** — not
disabled by a flag, not guarded by a boolean, *removed*. A flag can be flipped by
a future refactor that does not know what it is flipping; deleted code cannot.

Beyond asset fetching, the synthesis path MUST make zero network calls at
**synthesis time, model-load time, and voice-selection time**. Voice selection is
named explicitly because it is the one people forget: a picker that fetches a
preview or a voice list is a network call in the most privacy-sensitive feature
in the app.

**CI gate:** `TTS zero-egress source scan (spec 030 R1 / REQ-TTS-001)` — fails
the build, naming `REQ-TTS-001` and this spec, if `huggingface.co` or any
upstream host appears anywhere in the shipped dependency tree, or if networking
symbols are reachable from TTS sources. Demonstrated once against a planted
violation, per the house rule.

**Acceptance (Given/When/Then):**
- Given the shipped dependency tree, when scanned in CI, then zero
  `huggingface.co` references exist — the gate fails on a planted one.
- Given a device behind a capturing proxy, when model load, synthesis, and voice
  switching are each exercised, then **zero outbound requests** originate from
  TTS code. This capture is the artifact spec 036 archives; it is not optional
  evidence, it is the substantiation for a public claim.
- Given the vendored integration source, when audited, then no auto-download code
  exists to disable — because it is not present.

### R2. The model ships inside the app binary (`REQ-TTS-002`)

> **Rewritten 2026-08-18 (owner decision, `DEC-012`).** This requirement has been
> through two designs — self-hosted Background Assets, then Apple-hosted asset
> packs. **Both are withdrawn.** The model is now vendored into the repository and
> **bundled in the app**. There is no asset pack, no manifest served anywhere, no
> fetch, and no "not downloaded yet" state to design around.

The voice pack lives at `MeetMemento/Resources/Voices/` and ships as ordinary
app resources. The app target uses a `PBXFileSystemSynchronizedRootGroup`, so
files bundle **by existing in the folder** — no `project.pbxproj` edit is
required to add or remove them.

**Bundle layout is normative, because it is not what the folder implies.**
Synchronized groups **flatten every resource to the bundle root**. There is no
`Voices/` subdirectory at runtime; `VectorEstimator.mlmodelc` and `F1.json` sit
alongside `Figtree-Regular.ttf` and `SampleEntries.json`. Two consequences:

- The engine loads by **bare filename** from `Bundle.main`. Code written against
  a `Voices/` path will compile and fail at runtime.
- The root is a **shared namespace**. The upstream `config.json` is renamed
  **`voice_config.json`** for exactly this reason; anything else added here must
  be named as though it were global, because it is.

**Ship pre-compiled `.mlmodelc`, never `.mlpackage`.** The recipe compiles with
`xcrun coremlcompiler` and the compiled directories are what get vendored. This
removes any dependence on whether a synchronized group triggers Xcode's Core ML
build rule, and — the real prize — **eliminates runtime compilation entirely**.
First-ever model load no longer pays a multi-second compile, which was the single
worst thing that could land on a user's first spoken sentence. ANE specialization
on first load still occurs, so `031` R3's warm-up remains necessary.

**Shipping configuration** (see R7 for why these precisions):

| Asset | Precision | Size |
|---|---|---|
| `VectorEstimator.mlmodelc` | 8-bit palettized | 61.73 MB |
| `Vocoder.mlmodelc` | FP16, untouched | 48.41 MB |
| `TextEncoder.mlmodelc` | FP16 | 34.51 MB |
| `DurationPredictor.mlmodelc` | FP16 | 1.82 MB |
| `voice_styles/` | F1, F2, M1, M3 **only** | 1.12 MB |
| `voice_config.json`, `tts.json`, `unicode_indexer.json` | — | small |
| **Total** | | **~148 MB** |

**Acceptance (Given/When/Then):**
- Given a fresh install with **no network at any point**, when any voice feature
  is used, then the neural voice works — there is nothing to fetch.
- Given the built `.app`, when its contents are listed, then all four
  `.mlmodelc` directories, the three config files and exactly **four** style
  JSONs are present at the bundle root.
- Given the engine, when it resolves asset paths, then it uses bare filenames
  from `Bundle.main` and no code references a `Voices/` subdirectory.
- Given a first-ever synthesis on a clean device, when it runs, then **no CoreML
  compilation occurs** — asserted by instrumentation, since the shipped artifact
  is already compiled.

### R3. Integrity is a build-time property, not a runtime one (`REQ-TTS-002`)

The previous design verified SHA-256 on download, because assets arrived from
elsewhere and could arrive corrupted. **Bundled assets cannot.** They are signed
as part of the app bundle; iOS will not launch a binary whose contents fail code
signature validation, and there is no fetch to interdict.

So integrity moves left, to where it can still be got wrong: **the recipe**.

- `scripts/build_voice_pack.sh` pins the **SHA-256 of the base artifact's
  weights** and reports a mismatch loudly. Upstream republishing is not
  automatically fatal, but it MUST be investigated and the pinned table updated
  deliberately, never silently.
- The recipe is committed alongside its output. A model nobody can rebuild is a
  model nobody can update — including when a future CoreML format version forces
  a recompile.
- Model weights are large binaries and are tracked with **Git LFS**
  (`.gitattributes`). **CI checkout must set `lfs: true`** for any workflow that
  builds the app, or the build receives pointer files and fails at *runtime* as a
  model-load error rather than at build time.

**Acceptance (Given/When/Then):**
- Given the vendored pack, when `scripts/build_voice_pack.sh` is re-run against
  the pinned base, then it reproduces the shipped artifact.
- Given a base artifact whose checksum differs from the pinned table, when the
  recipe runs, then it reports the mismatch prominently rather than proceeding
  quietly.
- Given a CI workflow that builds the app, when its checkout step is inspected,
  then `lfs: true` is set.

### R4. Exactly four voices are vendored (`REQ-TTS-006`)

The base model publishes **ten** style vectors (F1–F5, M1–M5). Exactly four ship:
**F1, F2, M1, M3** (owner decision). The other six are **never copied into the
repository**, so there is no path — no flag, no config, no debug build — by which
an unshipped voice can appear in the picker. The roster is enforced by absence,
which is the only enforcement that cannot be bypassed.

Style vectors are small JSON and sit in the bundle like everything else. Spec
`033` owns how they are named and presented.

**Acceptance:** given the repository, when `MeetMemento/Resources/Voices/voice_styles/`
is listed, then it contains exactly four files; and given the built app, then the
picker can render no more than those four.

### R5. Degradation is a designed state, not an error path (`REQ-TTS-003`)

> **Narrowed 2026-08-18 (`DEC-012`).** This requirement was written for a
> downloaded model, where "assets absent / downloading / verifying" were routine
> states the app spent real time in. **Bundling deletes all of them.** The model
> is present on first launch, in airplane mode, forever.

The fallback therefore has exactly **two** remaining reasons to exist, and both
are genuine:

1. **Engine failure** — a load, inference, or format error. Per-utterance: that
   utterance completes on the system voice and the user hears speech either way
   (`031` R8).
2. **A device or OS below the neural path's minimum.** Static for the lifetime of
   the install.

Neither is a state the user can be in *temporarily by design*, which is the
substantive change: there is no longer a normal path through the app that starts
on the system voice and later improves.

When the fallback is serving it MUST still resolve the best available Enhanced or
Premium system voice — the shipped
`VoicePlaybackService.bestVoiceIdentifier(from:currentLanguage:)` ranking
(`:709`) is cited, not redesigned. What it MUST NOT do is nag: telling a user to
go download an Enhanced system voice made sense when that was the voice they
would keep, and makes no sense as guidance for a transient state they did not
choose (029 R8, amended). The user is not told about voices; they simply hear the
best one available.

Per CONSTITUTION rule 11, this path is **permanent**. It is no longer the
airplane-mode guarantee — bundling took that job — but it remains the insurance
policy against a third-party model meeting a future iOS release badly, and
against any synthesis failure producing silence instead of speech.

> **Conversation-boundary rule — retained, with a smaller job.** The engine in
> use is fixed for the lifetime of a conversation: a voice must never change
> under the user mid-session, because that is uncanny in a way slow synthesis
> never is.
>
> Bundling removes its original trigger (a download completing mid-session), but
> one remains: an engine that **failed on one utterance and recovers** must not
> silently swap voices back in the middle of the same conversation. It resumes at
> the next conversation. The rule does *not* govern a user-initiated change from
> the picker — a deliberate choice applies at the next chunk (`033` R4), because
> the user is expecting it and is listening for exactly that.

> **Amended 2026-08-18 — the neural voice ships on `CapabilityTier.reduced` too.**
> Read-aloud requires no language model, and with no AFM resident there is *more*
> memory headroom on those devices, not less. On a device where chat is
> unavailable, a good journal reader is arguably the best thing the tier has to
> offer, so gating voice behind the intelligence features would withhold the one
> capability that still works.
>
> **Architectural consequence, and it is binding:** the engine MUST NOT depend on
> anything AFM-related — no shared session, no `SystemLanguageModel` reference, no
> capability-tier gating *inside* the engine. The neural voice is the one
> intelligence-adjacent feature in this app that works on every supported device,
> and it stays that way only if nothing couples it to the model that doesn't.

**Acceptance (Given/When/Then):**
- Given a fresh install in **airplane mode**, when read-aloud and Narration Mode
  are used, then both work end-to-end **on the neural voice** — not the fallback.
  This is the criterion that changed most: the answer used to be "the system voice
  covers it."
- Given a forced engine failure mid-conversation, when the utterance is spoken,
  then it completes on the system voice, and the neural voice does **not** return
  until the next conversation.
- Given a user-initiated voice change from the picker mid-narration, when the next
  chunk plays, then it uses the new voice (`033` R4) — the conversation-boundary
  rule governs *automatic* switches only.
- Given a `CapabilityTier.reduced` device, when read-aloud is used, then the
  neural path is available on the same terms as any other device, and
  `grep -rn 'SystemLanguageModel\|CapabilityTier'` over the engine module returns
  nothing.

### R6. Attribution ships in the app — it is a licence term (`REQ-TTS-009`, `DEC-010`)

An **Acknowledgments screen** is added under Settings → About, following the
existing `SettingsSection`/`SettingsRow` composition in `AboutSettingsView.swift`
(App Information / Support / Legal / Share). It carries the model-weight
attribution required by the weights' licence.

**This closes a gap that predates TTS.** The app already ships three
OFL-licensed font families — Figtree, Lora, Manrope — and their `OFL.txt` sits in
`MeetMemento/Resources/Fonts/` referenced by no Swift file. The SIL Open Font
Licence requires that its copyright notice and permission notice ship with the
software. Whatever the current exposure is, the fix is the same screen, so the
font licences land here too rather than waiting for a spec that would never be
written.

Weight licensing is adjudicated in 018 R12, not restated here. The one product
consequence worth naming: the weights carry use-based restrictions (no
impersonation or deception) that are inapplicable to reading a user their own
journal — and that **re-open from scratch** the day any feature lets a user
generate audio in someone else's voice.

**Acceptance (Given/When/Then):**
- Given the shipped app, when Settings → About → Acknowledgments is opened, then
  the model-weight attribution string and the font licences are present — asserted
  by a UI test reaching the screen by accessibility identifier.
- Given the release that first includes the engine, when it is submitted, then
  the attribution is already present — this is a licence condition, so it ships
  *with* the engine, never in a follow-up.

### R7. Size is now app-binary size (`REQ-MON-005`, `DEC-012`)

Bundling moves the size question from "how big is the download" to **"how big is
the app"** — a harder constraint, because it is paid by every user at install
regardless of whether they ever use voice.

**The binding threshold is the App Store's "Ask If Over 200 MB" cellular
prompt.** It is not a hard block (iOS 13 removed that), but it is real install
friction on a first impression, and defending it is the whole reason the
precision choice below exists.

**RESOLVED 2026-08-18 — palettization brings this in under the threshold.**

| Graph | FP16 | Shipped | Why |
|---|---|---|---|
| `VectorEstimator` | 243.73 | **61.73** (8-bit) | 73% of the bundle; the only lever that matters |
| `Vocoder` | 48.41 | 48.41 | **Untouched** — quantization artifacts are audible here as ringing and metallic texture, and it is only 48 MB |
| `TextEncoder` | 34.51 | 34.51 | Small enough not to be worth the risk |
| `DurationPredictor` | 1.82 | 1.82 | Negligible |
| `voice_styles/` | 10 available | **4** — 1.12 | R4 |
| **Voice pack total** | 331.5 | **~148 MB** | |

Quality risk is confined to **one module at the mildest available setting**. The
size question is answered; **the quality question is not** — nothing ships until
the 8-bit build is compared by ear against the FP16 baseline (spec `036`, W2
protocol). If it degrades audibly, the response is to reconsider precision, not
to ship a worse voice.

**Measured, and the margin is thinner than projected:** the **debug simulator**
build is **180 MB**. That is the pessimistic figure — unthinned, uncompressed,
debug — but it is close enough to 200 MB that the gate must measure a **release
archive**, not a debug build, and must be an actual CI check rather than a memory.

`TESTFLIGHT_READINESS.md` records an expectation of "< 50 MB ideally". That
expectation is now void and must be updated rather than left to fail quietly.

**Acceptance (Given/When/Then):**
- Given a release archive, when its size is measured, then it is **under 200 MB**
  — enforced by a CI check, not by inspection.
- Given the shipped pack, when its contents are measured, then the totals match
  the table above.
- Given the 8-bit build, when compared by ear against FP16 on device, then a
  written verdict exists before release (`036`).

### R8. This spec's verification-queue ownership

**V31 — WITHDRAWN 2026-08-18.** It asked about App Review posture for a
self-hosted model pack, and the TLS/availability/CDN requirements for
Memento-controlled hosting. **Nothing is hosted.** The model is in the binary, so
every question V31 existed to answer is moot.

Recorded as withdrawn with the reason rather than deleted — the API findings it
produced (Background Assets, Apple-hosted limits) remain accurate and are
retained in `technology/13` §6/§6a for provenance, marked superseded.

This spec now owns **no open verification-queue items.** V29 (ANE placement) and
V30 (voice audition) belong to `031` and `033` respectively and are unaffected by
bundling, except that V29 must now be measured against the **palettized**
`VectorEstimator` — the artifact that actually ships.

**Acceptance:** V31 marked withdrawn in `technology/11-verification-queue.md`
with its reason, before this spec's status moves to done.

## Non-goals

- The engine itself, warm-up, and CoreML placement — spec 031.
- Streaming, chunking, and latency masking — spec 032.
- The picker UI and voice presentation — spec 033.
- Any audio-session change — specs 028 (current) and 034 (future) own that; this
  spec must not touch `AVAudioSession` configuration.
- Deciding whether the neural voice is default-on. Written here as default-on
  with the download beginning at first launch; if R7's measurement comes back
  large, that assumption is the first thing to revisit (see 036's open question).
- Voice cloning. The style extractor was never released and Voice Builder is
  closed — not buildable, do not spec.

## Acceptance

1. **Device, airplane mode, fresh install:** read-aloud and Narration Mode both
   work **on the neural voice** — not the fallback — and the picker renders
   exactly four voices with working previews. No crash, no hang, no error dialog.
2. **Build:** all four `.mlmodelc` directories, the three config files and exactly
   four style JSONs are present at the built bundle's **root**;
   `check_archive_hygiene.sh` passes.
3. **Device:** a first-ever synthesis performs **no CoreML compilation** — the
   shipped artifact is already compiled.
4. **Release archive under 200 MB**, enforced by CI rather than measured by hand.
5. **Proxy capture:** zero outbound requests from TTS code during model load,
   synthesis, and voice switching — archived per `036`. Now a formality rather
   than a finding, since there is no network code left in the path to exercise.
6. **Recipe:** `scripts/build_voice_pack.sh` reproduces the vendored pack from the
   pinned base, and reports a checksum mismatch loudly.
7. **CI:** `TTS zero-egress source scan (spec 030 R1 / REQ-TTS-001)` live and
   proven to fail on a planted violation; dependency allowlist **enforcing** and
   green; every app-building workflow checks out with `lfs: true`.
8. **UI test:** Settings → About → Acknowledgments reachable, showing model and
   font attribution.
9. **Recorded in this spec:** measured release-archive size, and V31's withdrawal.

## Regression Guards

- **CONSTITUTION rule 11** — the `AVSpeechSynthesizer` path is never removed. R5
  is that rule's implementation; a "cleanup" that deletes the fallback once the
  engine works breaks the airplane-mode guarantee and the OS-break insurance.
- **CONSTITUTION rule 12 / `REQ-TTS-001`** — no network in the synthesis path.
- **CONSTITUTION rule 8 / `REQ-PRIV-001`** — no content crosses to Z2. Asset
  delivery is content-free in both directions; keep it that way, and never add
  telemetry to it.
- **CONSTITUTION §2 (2026-08-18)** — the utterance-session seam and the
  audio-session ordering machinery are non-regression assets. This spec adds an
  asset lifecycle *behind* that seam and must not reshape it.
- **`REQ-POS-001` / spec 014 R3** — nothing in this spec's user-facing copy may
  use absolute-privacy phrasing. The proxy artifact substantiates the existing
  claim; it does not license a new one.
- **Spec 021 R6 / `REQ-MON-005`** — the allowlist governs the package; the
  manifest governs the weights. Neither substitutes for the other.

## Appendix A — shipped bundle layout

Vendored at `MeetMemento/Resources/Voices/`. **Flattened to the bundle root at
build time** — there is no `Voices/` directory at runtime (R2).

```
VectorEstimator.mlmodelc/     61.73 MB   8-bit palettized
Vocoder.mlmodelc/             48.41 MB   FP16
TextEncoder.mlmodelc/         34.51 MB   FP16
DurationPredictor.mlmodelc/    1.82 MB   FP16
voice_config.json                        (upstream config.json, renamed — R2)
tts.json
unicode_indexer.json
F1.json  F2.json  M1.json  M3.json       style vectors — exactly four (R4)
```

Reproduced by `scripts/build_voice_pack.sh <base-model-dir>`. Weights are tracked
with Git LFS; CI that builds the app must check out with `lfs: true` (R3).

## Appendix B — interface sketch

Contract, not implementation. Note how much smaller this is than the downloaded
design it replaces: no state machine, no progress, no verification, no retry —
because a bundled resource is either in the binary or the build is broken.

```swift
/// Zone: .z0Device. Locates bundled model assets. No network, no state.
enum VoicePack {
    /// Bare filenames — synchronized groups flatten to the bundle root (R2).
    static func modelURL(_ graph: Graph) -> URL      // e.g. .vectorEstimator
    static func styleURL(_ styleID: String) -> URL   // "F1" | "F2" | "M1" | "M3"
    static func configURL() -> URL                   // voice_config.json

    enum Graph: String {
        case vectorEstimator = "VectorEstimator"
        case vocoder = "Vocoder"
        case textEncoder = "TextEncoder"
        case durationPredictor = "DurationPredictor"
    }
}
```

There is deliberately no `TTSAssetState`, no `ensureAssets()`, and no
`TTSAssetManager` actor. The earlier design needed all three; this one cannot use
them, and their absence is the point.
