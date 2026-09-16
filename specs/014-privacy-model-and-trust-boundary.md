---
id: 014
title: Privacy Model and Trust Boundary
tier: P0
status: in-progress (2026-09-16) — R1 `TrustZone` + R3 positioning lint shipped. **R2 zone-at-point-of-use component does not exist** (zero `TrustZone` references in Views/Components), so P4 is aspirational; its quota branches are unreachable under `DEC-013`. **R4 `NetworkCallSiteAudit` does not exist**; egress verified by hand 2026-09-16 — one `URLSession` file, fail-closed, photo bytes device-local
effort: 1 session
depends_on: [013]
findings: [trust-zone-contract, zone-at-point-of-use-ui, positioning-claim-lint, network-call-site-audit, zone-ui-component-unbuilt, egress-is-one-call-site, revenuecat-not-integrated]
source_refs: [REQ-PRIV-001, REQ-PRIV-002, REQ-POS-001, DEC-013]
tech_refs: [technology/02-private-cloud-compute.md, technology/08-context-frameworks.md]
---

# 014 — Privacy Model and Trust Boundary

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§1.3 "Competitive position" (positioning claim, `REQ-POS-001`) and §3.2 "The trust
boundary, precisely" (Z0/Z1/Z2 zones, `REQ-PRIV-001`, `REQ-PRIV-002`).

## Why

Every other 2.0 spec assumes a settled answer to "which zone does this operation
run in, and how is that shown to the user." This spec establishes that contract
first (P4: "the trust boundary is a UI element, not a policy page") so specs
015–022 can cite it rather than each inventing their own zone-tagging convention.
It's also where the positioning claim in §1.3 becomes an enforceable rule
(`REQ-POS-001`) rather than marketing copy someone can accidentally contradict in
an unrelated surface.

## Technology References

- `specs/reference/technology/02-private-cloud-compute.md` — Z1 degradation
  contract (`.belowLimit`/`isApproachingLimit`/`isLimitReached`, automatic and
  disclosed on-device fallback) that this spec's zone contract must be able
  to represent.
- `specs/reference/technology/08-context-frameworks.md` — the Z0-only
  summarization rule for ambient context (HealthKit/weather/location), a
  concrete instance of the zone boundary this spec defines.

## Current State (evidence)

N/A — greenfield. No `TrustZone` enum, no zone-declaration convention, and no
positioning-claim guard exists in the current (pre-2.0) codebase.

## Requirements

**Traceability:** R1 → `REQ-PRIV-002`; R2 → P4, P5, `technology/02-private-cloud-compute.md`
§6/§8; R3 → `REQ-POS-001`; R4 → `REQ-PRIV-001`. Every generation surface built
in specs 016/017/018/019 declares a zone via R1's contract and renders it via
R2's component — this spec defines both once so they aren't reinvented per
surface (P4).

### R1. `TrustZone` interface contract
A `TrustZone` enum, not a `Bool`/string, so the compiler — not convention —
enforces that every content-touching operation states where it ran:

```swift
/// The innermost zone an operation required, per architecture spec §3.2.
/// There is no `.z2` case: REQ-PRIV-001 requires content never cross into
/// Z2 under any configuration, so a type that could represent Z2-tagged
/// content would itself be a way to violate that rule. Z2 (RevenueCat
/// receipts + anonymous ID only, spec 021) never carries anything this
/// enum tags.
enum TrustZone: Equatable, Codable {
    /// Never leaves this device. Works in airplane mode. Transcription,
    /// entry reflection, mood/tag inference, retrieval, search, TTS.
    /// Multi-device replica of journals/chats/profile is the user's
    /// CloudKit private DB (Z1, spec 040) — not a Memento account.
    case z0Device

    /// Leaves the device to Apple's attested infrastructure, carrying
    /// journal content. PCC generation: weekly, monthly, chat.
    case z1AppleContent(reasoningLevel: PCCReasoningLevel)

    /// Leaves the device to Apple's infrastructure but carries **no**
    /// journal content — e.g. WeatherKit (a location, never entry text).
    /// Distinct from `.z1AppleContent` because REQ-PRIV-001's guarantee is
    /// about content specifically; collapsing this into either `.z0Device`
    /// (false — it's a real network call) or `.z1AppleContent` (false —
    /// implies content exposure that never happens) would misrepresent it
    /// either way. `technology/08-context-frameworks.md` §4 is the concrete
    /// case this exists for.
    case z1AppleContentFree
}

enum PCCReasoningLevel: String, Codable {
    case light, moderate, deep
}
```

Every `GenerationRequest` carries a `zone: TrustZone` set **before** the call
is made (not inferred after, which would let a misrouted call go undetected);
every `GenerationOutcome`/`Reflection`/`Turn` persists the zone it actually
ran in, which may differ from the requested zone after Z1→Z0 degradation
(R2). Content-free Z1 calls (WeatherKit) carry `.z1AppleContentFree` on
whatever their own request type is — they are not `GenerationRequest`s.

**Acceptance:** `TrustZone` compiles with these 4 cases (3 zone kinds, one
parameterized); a code-review/lint rule (or, if feasible, a compile-time
check) rejects any new `GenerationRequest`-conforming type that lacks a
`zone` property; unit test constructs one instance of each case and confirms
`Codable` round-trip (needed for persistence in spec 015's `Reflection.zone`/
`Turn.wasDegraded` fields).

### R2. Zone-at-point-of-use UI component

> **Amended 2026-09-16 (`DEC-013`, spec 017 R11) — unbuilt, and the state
> machine below is now unreachable.**
>
> **The component does not exist.** `grep -rl TrustZone MeetMemento/Views
> MeetMemento/Components` returns **zero files**, so **P4** ("the trust boundary
> is a UI element, not a policy page") is currently aspirational rather than
> shipped. That is the single largest gap between this spec and the app.
>
> **The quota lifecycle it renders cannot occur.** `DEC-013` makes every intent
> Z0; `QuotaGovernor.capability(for:)` is never called; `wasDegraded` is
> structurally `false`. So `.approachingLimit`, `.limitReached` and the
> degradation copy below describe states no user can reach, and
> `DeviceCopy.writtenOnDevice` — cited by the error-taxonomy table and consumed
> by spec 017 R4 — **does not exist and should not be added**.
>
> **What P4 needs under `DEC-013` is smaller and more honest.** Not a quota
> state machine, but a single legible statement that generation happened on this
> device, available at the point of use. The `.unavailable` state (no Apple
> Intelligence capability) is the one branch below that remains real and still
> needs a component — it is the Reduced tier's honest explanation
> (`REQ-PLAT-004`).
>
> Retained below as the contract PCC would re-enter under. Do not implement the
> quota branches while `DEC-013` stands.

One reusable SwiftUI component (not per-surface bespoke copy) rendering
`TrustZone` at the point of use, per P4 ("legibility is the product") — every
consuming spec (016–019) uses this component rather than writing its own
zone copy.

**State machine** (per architecture spec §17's requirement for multi-step/
async flows — this one is the quota lifecycle a Z1 affordance moves through):

```
                    ┌─────────────┐
                    │ .unavailable│  (no Apple Intelligence on this device —
                    └──────┬──────┘   Reduced tier; always this state there)
                           │ AI capability detected
                           ▼
                    ┌─────────────┐
              ┌────▶│ .available  │
              │     └──────┬──────┘
              │            │ quotaUsage.status == .belowLimit,
              │            │ !isApproachingLimit
              │            ▼
              │     ┌─────────────────┐
              │     │.approachingLimit│  persistent inline state, not an alert
              │     └────────┬────────┘
              │              │ isLimitReached
              │              ▼
              │     ┌─────────────┐
              └─────┤ .limitReached│  degrades to Z0 automatically (R2 below)
     new day/  quota resets
     limit increase
```

**Error taxonomy** (design copy, not developer strings — architecture §17):
| State | Copy (draft — final wording owned by design) |
|---|---|
| `.unavailable` | *"This reflection runs on this device — deeper synthesis needs a newer device."* |
| `.approachingLimit` | *"Nearing today's reflection limit."* (persistent, dismissible, never a modal alert — `technology/02-private-cloud-compute.md` §6, Apple's own explicit guidance) |
| `.limitReached`, pre-degradation | *"Today's deeper-reflection limit is used up."* |
| Degraded Z1→Z0 (post-hoc, rendered on the artifact itself) | *"Written on this device. Shorter than usual — your daily reflection allowance is used up until tomorrow."* (`DeviceCopy.writtenOnDevice`; editable by design but not by each surface independently) |

**Degradation behavior** (architecture §17's requirement, non-negotiable per
`technology/02-private-cloud-compute.md` §8): Z1→Z0 degradation is attempted
automatically, completed successfully, and disclosed — both persisted
(spec 015's `Reflection.zone`/`Turn.wasDegraded`) and rendered via this same
component. Degraded generations MUST use a prompt tuned for the on-device
model, never the PCC prompt run against a smaller model (owned procedurally
by spec 017's `PromptRegistry`, but the *contract* that a degradation-specific
prompt variant must exist is stated here since it's what R2's disclosure UI
promises the user is actually true).

**Acceptance (Given/When/Then):**
- Given a Z1-eligible surface on a device with Apple Intelligence available
  and quota below limit, when the zone component renders, then it shows
  `.available` with no quota copy.
- Given `quotaUsage.isApproachingLimit`, when rendered, then it shows
  persistent inline copy (not a system alert) and remains interactive.
- Given `quotaUsage.isLimitReached` and a Z1 request is attempted, when the
  request executes, then it automatically retries at `.z0Device`, the
  resulting artifact persists `wasDegraded == true`, and the rendered
  component shows the degradation copy above — never a silent, unlabeled
  Z0 result.
- Given a device with no Apple Intelligence capability at all, when any
  Z1-eligible surface renders, then it shows `.unavailable` unconditionally
  (never attempts the Z1 call, never shows quota UI that implies a capability
  that isn't there).

### R3. `REQ-POS-001` compliance rule — checkable, not a written policy
**The rule:** no marketing copy, App Store listing text, or in-app string MAY
contain (case-insensitive, substring match) any of: *"nothing leaves your
phone," "no network calls," "airplane mode proves it,"* or equivalent
absolute-privacy phrasing, **while any surface in the app has PCC routing
enabled** — ~~which, per the routing table (spec 017's `REQ-INT-003`), is
effectively always true for a shipping build with weekly/monthly/chat live,
regardless of what a given user's current settings or connectivity happen to
be.~~ The claim is about the app's *capability*, not a snapshot of one user's
session.

> **Amended 2026-09-16 (`DEC-013`, spec 017 R11) — the premise inverted, and the
> rule stays in force anyway.**
>
> The struck clause said PCC routing is "effectively always true for a shipping
> build." Under `DEC-013` it is **never** true: no surface has PCC routing
> enabled, and no `TrustZone` value carrying content off-device is ever
> constructed at runtime. Read literally, the rule's trigger condition is now
> unsatisfied and the forbidden phrases would be permitted.
>
> **Do not relax the lint on that reasoning.** Three arguments against, in order
> of weight:
>
> 1. **The capability framing still binds.** The seam is one conformance away
>    from live (`PCCSessionProviding`), and the rule exists precisely so that
>    flipping a construction site cannot silently falsify shipped copy. A lint
>    that has to be re-tightened whenever the architecture changes is not a
>    guard.
> 2. **CloudKit mirroring makes the strongest phrases false regardless of PCC.**
>    `"nothing leaves your device"` and `"100% on-device"` are untrue of a build
>    with `cloudKitDatabase: .private(...)` live (`JournalContainer.swift:59-63`),
>    whatever the intelligence layer does. **P2** already says this: *"Do not
>    claim the journal is 100% on-device while CloudKit mirroring is enabled."*
> 3. **Precision beats absolutism commercially.** See `REQ-POS-001` as amended —
>    the claim available on the facts ("one network call, off by default, no
>    server, no account, photo bytes never leave the device") is *more*
>    persuasive than the forbidden phrasings and survives audit, which the
>    absolutist phrasings would not.
>
> **The lint's phrase list is unchanged and `lint_forbidden_phrases.py` is not to
> be edited under `DEC-013`.** Its scope is `*.swift` string literals and `*.txt`
> App Store metadata; it does not scan `.md`, so specs may quote forbidden
> phrases freely — as this amendment does.
>
> One live violation exists in the **opposite** direction, which this lint
> structurally cannot catch: `DataUsageInfoView.swift:123` claims PCC *may* be
> used. Owned by spec 017 R11, Current State row 4.

**Acceptance:**
- A static-string lint (grep-based is sufficient — this doesn't need NLP)
  runs in CI against `MeetMemento/**/*.swift` string literals and
  `App Store Connect` metadata source (wherever spec 002 keeps it) for the
  forbidden-phrase list above; a match fails the build/PR check.
- Given/When/Then: given the forbidden-phrase lint, when a string literal
  containing "nothing leaves your phone" is added anywhere in the app
  target, then CI fails with a message pointing at `REQ-POS-001` and this
  spec, not a generic lint failure.
- The positioning claim itself (`REQ-POS-001`'s own verbatim text: *"No
  account. No analytics. No third-party AI. Your words are processed on your
  iPhone, or on Apple's Private Cloud Compute, which stores nothing and is
  independently verifiable. Nothing else."*) is the one string explicitly
  exempted from the lint — it's the rule's source, not a violation of it.
  (Already live: `WelcomeView.swift`'s `welcome.positioning` text, spec 023 R2.)

> **R3 landed 2026-08-02:** the forbidden-phrase lint is implemented and wired
> (`scripts/ci/lint_forbidden_phrases.py`, `.github/workflows/spec-gates.yml`).
> It is comment-aware (scans string literals only, so a comment *mentioning* a
> phrase is not a violation), scans `MeetMemento/**/*.swift` plus ASC metadata
> `.txt` if present, and honors a `// REQ-POS-001-EXEMPT` line marker (and
> `// REQ-POS-001-EXEMPT-FILE`) for the positioning claim. Green on the current
> tree; verified to fail on a planted forbidden literal and to respect the
> exemption. This satisfies R3's acceptance. (R1/R2/R4 remain pending the Swift
> `TrustZone` type + zone UI component.)

### R4. `REQ-PRIV-001` acceptance criteria — verified in tests, not asserted in prose

> **Amended 2026-09-16 — `NetworkCallSiteAudit` does not exist, and the boundary
> it was written to police has three fewer surfaces than this R-block assumes.**
>
> **The audit is unbuilt.** No such test file exists in `MeetMementoTests/`. The
> nearest real artifacts are `scripts/ci/check_tts_zero_egress.sh` (narrow — greps
> `MeetMemento/Services/Voice` + `Packages/SupertonicTTS` for
> `huggingface.co|hf.co/|download.*mlmodel`) and
> `scripts/ci/check_dependency_allowlist.sh`. R4's Verification checkbox stays
> open.
>
> **The verified egress inventory, 2026-09-16.** Exhaustive grep across
> `MeetMemento/`, `MeetMementoWatch/`, `Packages/` and `Fixtures/`:
>
> | Surface | Sites |
> |---|---|
> | `URLSession` / `URLRequest` | **One file**: `Services/Feedback/SupabaseFeedbackClient.swift:5,65,75,100` |
> | `Network` framework, `WebKit`, `WeatherKit`, `HealthKit` | **zero** |
> | Third-party SPM | **zero remote packages.** Only the local `Packages/SupertonicTTS`, which declares no dependencies. No `Package.resolved` exists |
> | PCC | **zero** — `DEC-013` / spec 017 R11 |
> | CloudKit | `SyncStatusStore.swift:9` (account status), `FiveStoreDeletion.swift:10,121` (`CKModifyRecordsOperation`), plus implicit SwiftData mirroring at `JournalContainer.swift:59-63` |
> | StoreKit | `import StoreKit` once, at `AboutSettingsView.swift:10`. No products, no paywall, no `Transaction.currentEntitlements` |
>
> So the boundary has **two** destinations, not five: Apple CloudKit private DB,
> and the operator's Supabase RPC endpoint.
>
> **Three of the five categories this R-block enumerates have no call sites at
> all.** WeatherKit is never called, so `.z1AppleContentFree` is constructed only
> in tests and matched in exhaustive switches — location is used, but purely
> on-device (`EntryLocationService.swift:10,76,148` reverse-geocodes at
> `kCLLocationAccuracyReduced` and discards the `CLLocation`, returning a place
> string). **RevenueCat is not integrated** — it appears only as a TARGET entry in
> `specs/dependency-allowlist.txt` and as a comment at `TrustZone.swift:22`, so
> spec 021's Z2 exception is currently unexercised. PCC is `DEC-013`.
>
> **The Supabase leg is fail-closed.** `FeedbackSupabaseConfig.fromBundle()`
> returns `nil` when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are absent, and both
> `Config/Debug.xcconfig` and `Config/Release.xcconfig` ship them **empty** with
> an optional `#include?`. **A fresh clone makes zero network calls of any kind.**
> Combined with ratings being off by default (`FeedbackConsent.swift:22`), this is
> the strongest factual basis for `REQ-POS-001` as amended.
>
> **Photo bytes never leave the device.** `MementoDataStore.swift:56-62` mirrors
> only a `StoredAttachment` with `kind = "photo"` and `fileAssetID`; the JPEG
> lives in `Documents/EncryptedPhotos` under the device DEK, which is never
> mirrored. Spec [046](046-photo-capture-and-multimodal-recall.md) owns this.
>
> **What R4 should actually assert, if built.** The five-way classification is
> over-specified for a two-destination boundary. A simpler and stronger guard:
> assert that `URLSession`/`URLRequest` appears in exactly one file, and that the
> file is `SupabaseFeedbackClient.swift`. That is a one-line CI grep, it is
> currently true, and it fails loudly the moment a second egress point is added.

**Given/When/Then:**
- Given any `GenerationRequest` constructed anywhere in the codebase, when
  its `zone` is inspected, then it is never a value that could route content
  to a third party — mechanically guaranteed by R1's `TrustZone` enum having
  no Z2 case, not by developer discipline.
- Given the full set of network-call sites in the app (Foundation Models/PCC,
  WeatherKit, CloudKit, RevenueCat, and any future addition), when each is
  classified, then every one is tagged `.z0Device` (no network),
  `.z1AppleContent`/`.z1AppleContentFree` (Apple infrastructure), or is
  RevenueCat's explicit, spec-021-owned Z2 exception (receipts + anonymous ID
  only — never a `TrustZone`-tagged call at all, since it never carries
  content), or spec 042's named `Z2ContentException.answerFeedbackVerification`
  (volunteered answer feedback for quality verification — not a
  `GenerationRequest`, not a TrustZone case). There is no unclassified
  fourth category.

**Test plan** (Swift Testing, naming the specific fixture this spec
introduces): a `NetworkCallSiteAudit` test (or CI-run script, whichever the
codebase's existing convention favors — check spec 011's test-foundation
patterns before choosing) that statically enumerates every `URLSession`/
`PrivateCloudComputeLanguageModel`/`WeatherService`/CloudKit/RevenueCat call
site in the built target and asserts each carries a `TrustZone` tag or is on
the RevenueCat allowlist. This is the mechanical version of the manual grep
audit spec 023 did by hand for its own "zero network calls" claim
(`specs/023-no-account-experience.md` Task 8) — R4 turns that one-off manual
technique into a standing, automated guard so future specs can't silently
regress it.

### R5. This spec's §16 verification-queue ownership
Confirmed: none of the source document's §16 items are directly owned by
this spec (verified against the current `technology/11-verification-queue.md`
mapping — items 5/6, the entitlement filings this spec's Why section doesn't
touch, are owned by spec 013 R5, already researched and documented there
2026-07-23). No `⚠️ VERIFY` markers in this spec's own text remain
unaddressed.

## Out of Scope

- The actual routing table deciding which intent defaults to which zone —
  that's `REQ-INT-003`, owned by spec 017 (this spec defines the zones and the
  disclosure contract; 017 decides which surface uses which zone by default).
- RevenueCat's Z2 exception (purchase receipts + anonymous ID) — owned by spec 021.
- **`Z2ContentException.answerFeedbackVerification` (added 2026-09-11, spec
  [042](042-feedback-telemetry-supabase.md)).** A named, bounded exception
  for volunteered in-app chat feedback (thumbs, why-reasons, Report). It
  may carry journal-derived `userPrompt` / `assistantReply` **only** on an
  explicit Report with a per-submission include-text switch, and only when
  the Settings toggle (off by default) is on. Thumbs-only is metadata
  (rating, category, volunteered note, prompt/model/zone, citation
  **count**). Write-only RPC; no client SELECT; no journal sync; remote
  erase on Delete Everything / toggle off. This is **not** a
  `GenerationRequest` and must not be tagged with `TrustZone`. When R4's
  `NetworkCallSiteAudit` is built, `SupabaseFeedbackClient` is allowlisted
  beside RevenueCat with the consent gate asserted.

## Tasks
- [x] 1. Define the `TrustZone` interface contract and where it's declared on
      requests/results (R1). **Spec written 2026-07-23** — see R1 above for
      the full `TrustZone`/`PCCReasoningLevel` contract. **Not yet
      implemented as an actual Swift file**: `TrustZone` has no consumers
      until spec 016/017 build the retrieval/intelligence layer that would
      construct `GenerationRequest`s, so creating `TrustZone.swift` in
      isolation now would be premature — implementation lands alongside
      whichever of 016/017 needs it first, per this spec's own contract.
- [x] 2. Specify the UI pattern for rendering zone-at-point-of-use (a reusable
      component, not per-surface bespoke copy) (R2). **Spec written
      2026-07-23** — state machine, error-taxonomy copy table, and
      degradation-behavior contract all in R2 above. Same as R1: no
      implementation yet, no consumer surface exists before spec 019.
- [x] 3. Write the `REQ-POS-001` compliance rule as a checkable acceptance
      criterion (R3). **Spec written 2026-07-23** — forbidden-phrase list,
      lint mechanism (grep-based CI check), and the explicit exemption for
      the positioning claim's own verbatim text. **This one has an existing
      consumer today**: `WelcomeView.swift`'s `welcome.positioning` string
      (spec 023 R2, already shipped) — the CI lint itself isn't wired up
      yet; that's a small, immediately-actionable follow-up task, not
      gated on any other spec.
- [x] 4. Write Given/When/Then acceptance criteria for `REQ-PRIV-001` (R4).
      **Spec written 2026-07-23** — see R4 above, including the
      `NetworkCallSiteAudit` test-plan concept that generalizes the manual
      network-call grep spec 023 did by hand (`023-no-account-experience.md`
      Task 8) into a standing, automated guard.
- [x] 5. Its subset of the source doc's §16 verification queue: none directly
      owned by this spec — confirm that's still true when this spec is picked
      up (R5). **Confirmed 2026-07-23** against the current
      `technology/11-verification-queue.md` — no items map to this spec.

## Verification
- [ ] `TrustZone.swift` exists, compiles with the 4 cases in R1, and has a
      passing `Codable` round-trip unit test — lands with spec 016 or 017
      (whichever implements first), not this spec directly.
- [ ] The zone-at-point-of-use component (R2) exists and its 4 Given/When/Then
      acceptance criteria each have a corresponding UI test — lands with
      spec 019 (Surfaces), the first spec with real Z1-affordance UI to test
      against.
- [ ] `REQ-POS-001` forbidden-phrase CI lint is wired up and passing against
      the current codebase (including `WelcomeView.swift`'s exempted
      positioning string) — **immediately actionable, not gated on any other
      spec**; do this the next time CI config is touched.
- [ ] `NetworkCallSiteAudit` (R4) exists, enumerates every network call site
      in the built target, and passes — lands once specs 016/017/021
      (Spotlight, PCC, RevenueCat) exist to give it something to audit;
      until then there's nothing to enumerate.
- [ ] `CONSTITUTION.md` §4 rule 8 (`REQ-PRIV-001`/`REQ-POS-001`, already
      pointing at this spec) is satisfied by the above once implemented —
      re-confirm at that point, not just this spec's own local tests.

## Regression Guards
None yet (greenfield). Once implemented, this spec's own `REQ-PRIV-001` /
`REQ-POS-001` become standing rules 8/enforcement items in `CONSTITUTION.md` §4
(already added there, pointing back at this spec) — this spec's Verification
section should confirm those `CONSTITUTION.md` rules are satisfied, not just its
own local tests.
