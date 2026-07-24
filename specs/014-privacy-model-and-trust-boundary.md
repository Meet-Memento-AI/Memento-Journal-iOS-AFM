---
id: 014
title: Privacy Model and Trust Boundary
tier: P0
status: not-started
effort: 1 session
depends_on: [013]
findings: []
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

- [ ] TODO (derive from source doc, following its §17 "Derived spec checklist"):
  interface contract for the `TrustZone` enum and the zone-declaration convention
  every `GenerationRequest`/`GenerationOutcome` must carry (`REQ-PRIV-002`); the
  exact UI treatment for showing zone at point of use; a concrete, testable rule
  for what marketing/App Store/in-app copy MUST NOT claim while PCC routing is
  enabled (`REQ-POS-001`) — e.g. a lint or review checklist, not just a written
  policy; Given/When/Then acceptance criteria for "no journal content crosses into
  Z2 under any configuration" (`REQ-PRIV-001`), including how that's verified in
  tests rather than asserted; a classification for **content-free Apple network
  calls** that are neither Z0 nor content-carrying Z1 — WeatherKit is the concrete
  case (`technology/08-context-frameworks.md` §4: the request carries a location,
  never journal content; off by default, disclosed in the privacy explainer) — so
  the zone model can represent them honestly instead of forcing a false choice;
  and the quota/degradation disclosure UI contract: Apple's verified guidance
  (`technology/02-private-cloud-compute.md` §6) is **persistent, actionable
  inline state — never alerts** — for quota states, which is P5 made concrete
  and belongs in this spec's zone-at-point-of-use UI component, not re-invented
  per surface.

## Out of Scope

- The actual routing table deciding which intent defaults to which zone —
  that's `REQ-INT-003`, owned by spec 017 (this spec defines the zones and the
  disclosure contract; 017 decides which surface uses which zone by default).
- RevenueCat's Z2 exception (purchase receipts + anonymous ID) — owned by spec 021.

## Tasks
- [ ] 1. Define the `TrustZone` interface contract and where it's declared on
      requests/results.
- [ ] 2. Specify the UI pattern for rendering zone-at-point-of-use (a reusable
      component, not per-surface bespoke copy).
- [ ] 3. Write the `REQ-POS-001` compliance rule as a checkable acceptance
      criterion (what exact phrases are forbidden, under what conditions).
- [ ] 4. Write Given/When/Then acceptance criteria for `REQ-PRIV-001`.
- [ ] 5. Its subset of the source doc's §16 verification queue: none directly
      owned by this spec — confirm that's still true when this spec is picked up.

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written.

## Regression Guards
None yet (greenfield). Once implemented, this spec's own `REQ-PRIV-001` /
`REQ-POS-001` become standing rules 8/enforcement items in `CONSTITUTION.md` §4
(already added there, pointing back at this spec) — this spec's Verification
section should confirm those `CONSTITUTION.md` rules are satisfied, not just its
own local tests.
