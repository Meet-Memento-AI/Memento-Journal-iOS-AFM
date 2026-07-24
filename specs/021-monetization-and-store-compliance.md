---
id: 021
title: Monetization and Store Compliance
tier: P1
status: not-started
effort: 2 sessions
depends_on: [017]
findings: []
source_refs: [REQ-MON-001, REQ-MON-002, REQ-MON-003, REQ-MON-004, REQ-MON-005, DEC-001, DEC-004]
tech_refs: [technology/10-monetization-and-privacy.md]
---

# 021 — Monetization and Store Compliance

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§12 "Monetization and dependencies" in full, plus `DEC-001` from §4.1 "Capability
matrix" (paywall presentability on Reduced-tier devices).

## Why

Marginal inference cost is now ~zero for both Memento and its reference
competitor Slate, so pricing can no longer be justified by COGS — this spec
carries the pricing *decision* (`DEC-004`) plus its *implementation*
(StoreKit 2 + RevenueCat) and the store-compliance consequence of the whole
rewrite: the target "Data Not Collected" privacy label (`REQ-MON-004`), which is
worth more than RevenueCat's subscriber-analytics dashboard if the two conflict.

## Technology References

- `specs/reference/technology/10-monetization-and-privacy.md` — primary:
  StoreKit 2 + RevenueCat integration pattern, Small Business
  Program/PCC eligibility chain, the RevenueCat data-minimization rule
  (`REQ-PRIV-001`), and the "Data Not Collected" privacy-label target
  (`REQ-MON-004`).

## Current State (evidence)

Existing monetization code (`MeetMemento/Views/.../Monetization`,
`SubscriptionPlan.swift` model) targets the current $9.99/mo /$79/yr plan against
the pre-2.0 backend; `MeetMemento/PrivacyInfo.xcprivacy` currently declares
collected data types (User Content, Email, Name, User ID) that describe the
Supabase backend being deleted — flagged stale in `CONSTITUTION.md` §2 *Store
compliance*, to be corrected by this spec.

## Requirements

- [ ] TODO (derive from source doc §12, per its §17 checklist): resolve `DEC-004`
  (final price/trial length — source doc gives observations, not a conclusion:
  Slate's $7.99/$59.99 with 1-month trial de-risks the model, Memento's larger
  feature surface can defend a premium but the exact premium should be tested);
  resolve `DEC-001` (ship on Reduced-tier devices? source doc recommendation:
  yes, but gated to free-forever capture-only with no paywall presentation —
  confirm this against spec 015's `REQ-PLAT-004` tier-resolution logic);
  StoreKit 2 + RevenueCat integration contract (`REQ-MON-001`) with the hard
  constraint that RevenueCat receives purchase events + anonymous ID only, never
  content — **and with no accounts (spec 023, 2026-07-23), the anonymous
  app-user ID is the only identifier that exists**, which strengthens the
  `REQ-MON-004` "Data Not Collected" case, and makes StoreKit's **Restore
  Purchases the sole cross-device entitlement path** — it MUST be prominent in
  the paywall UI, since there is no account to "log back into"; App Review
  posture also improves: guideline 2.1's demo-account requirement is **moot**
  (nothing is sign-in gated), removing what spec 002 flagged as a mandatory
  reviewer-account chore; Small Business Program enrollment confirmation
  (`REQ-MON-002`, cross-check against spec 013's R5 filing); free-vs-paid feature gating
  (`REQ-MON-003`: capture/transcription/timeline/search/export always free;
  reflections/patterns/ask/Personal Voice paid); `REQ-MON-004`'s privacy-label
  target with ⚠️ VERIFY item 12 (does RevenueCat's SDK itself trigger a
  collection disclosure — if so, evaluate StoreKit 2 direct and accept losing
  subscriber analytics, per the source doc's explicit priority ordering);
  dependency-allowlist governance (`REQ-MON-005`).

## Out of Scope

- Which specific surfaces are gated behind the paywall beyond the free/paid split
  in `REQ-MON-003` — that's each surface spec's (019, 018) concern to implement;
  this spec sets the policy.
- App Store Connect metadata mechanics beyond the privacy label — largely spec
  002's pre-2.0 scope; this spec only owns what changes *because of* the
  architecture rewrite (privacy label, data-collection disclosures).

## Tasks
- [ ] 1. Resolve `DEC-004` (pricing/trial).
- [ ] 2. Resolve `DEC-001` (Reduced-tier shipping posture).
- [ ] 3. Implement StoreKit 2 + RevenueCat per `REQ-MON-001`.
- [ ] 4. Confirm Small Business Program enrollment status against spec 013's
      filing (`REQ-MON-002`).
- [ ] 5. Implement free/paid feature gating (`REQ-MON-003`).
- [ ] 6. ⚠️ VERIFY item 12: RevenueCat SDK vs. "Data Not Collected" label;
      update `PrivacyInfo.xcprivacy` accordingly (`REQ-MON-004`).
- [ ] 7. Document the dependency allowlist governance process (`REQ-MON-005`).

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include item 12 of the source doc's §16 verification queue marked
      confirmed or outstanding, and a confirmed target privacy label (Data Not
      Collected or the fallback if RevenueCat forces a disclosure).

## Regression Guards
`CONSTITUTION.md` §2 *Store compliance* flags `.xcprivacy` as stale pending this
spec — closing this spec must resolve that flag, not leave it dangling.
`REQ-PRIV-001` (spec 014, `CONSTITUTION.md` §4 rule 8) bounds what RevenueCat may
ever receive — content and derived data are never in scope for this integration.
Preservation contract: the paywall (ATTACH-07) gates only
reflections/patterns/ask/Personal Voice per `REQ-MON-003` — the free-tier
surfaces (capture, timeline, search, export; PRES-020…026, PRES-085's export
row) must remain reachable without any purchase or prompt.
