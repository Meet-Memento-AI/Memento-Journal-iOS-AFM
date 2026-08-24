---
id: 014
title: Privacy Model and Trust Boundary
tier: P0
status: in-progress (2026-07-23) — Requirements written (R1-R5); Swift implementation deferred to specs 016/017/019, which are its first real consumers
effort: 1 session
depends_on: [013]
findings: [trust-zone-contract, zone-at-point-of-use-ui, positioning-claim-lint, network-call-site-audit]
source_refs: [REQ-PRIV-001, REQ-PRIV-002, REQ-POS-001]
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
enabled** — which, per the routing table (spec 017's `REQ-INT-003`), is
effectively always true for a shipping build with weekly/monthly/chat live,
regardless of what a given user's current settings or connectivity happen to
be. The claim is about the app's *capability*, not a snapshot of one user's
session.

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
  content) — there is no fourth category.

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
