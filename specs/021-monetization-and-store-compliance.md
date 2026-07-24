---
id: 021
title: Monetization and Store Compliance
tier: P1
status: in-progress (2026-07-24) — Requirements derived; DEC-001/DEC-004 open product decisions, V8 privacy-label verification outstanding
effort: 2 sessions
depends_on: [017]
findings: [dec-004-pricing-open, dec-001-reduced-tier-open, revenuecat-z2-data-diet, privacy-label-verify-first, dependency-allowlist-ci-lint, sbp-pcc-eligibility-ops]
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

**Traceability:** R1 → §12.1, `DEC-004` (OPEN); R2 → `DEC-001` (OPEN),
`REQ-PLAT-004` (tier signal owned by spec 015 R7, policy owned here); R3 →
`REQ-MON-001`; R4 → `REQ-MON-003`; R5 → `REQ-MON-004`, source doc §16 item 12
(→ V8); R6 → `REQ-MON-005`; R7 → `REQ-MON-002` (filing process owned by spec
013 R5, cited not re-derived); R8 → §16 verification-queue ownership. The Z2
data boundary is **not** redefined here: spec 014 R4 already defines RevenueCat
as the sole allowed Z2 exception (purchase receipts + anonymous ID only, never
content, never a `TrustZone`-tagged call) — R3 implements that exception, it
does not renegotiate it. Quota/upsell copy rules are owned by spec 017 R3
(`REQ-INT-008`); R4 constrains the paywall so it can never blend with them.

### R1. Pricing posture — `DEC-004` OPEN, do not resolve here silently
Source doc §12.1 gives **observations, not a conclusion** — this spec records
the decision space and the constraint set; the decision itself is a product
call still pending:

- **Facts to reason from** (§12.1, `technology/10` §2): marginal inference
  cost is ~zero for both Memento and Slate — neither can justify price by
  COGS; Slate ($7.99/mo, $59.99/yr, 1-month trial) has demonstrated consumers
  pay a subscription for a zero-marginal-cost local app, which de-risks the
  model; Memento's feature surface is materially larger, so a premium is
  defensible — but a 25–33% premium (current plan: $9.99/mo, $79/yr) is a
  specific claim about perceived value that should be **tested, not assumed**
  (the willingness-to-pay ≥ 70% end-of-study metric, `REQ-EVAL-002`, is the
  natural instrument).
- **Option A — match Slate** ($7.99/$59.99, 1-month trial): removes price as
  a comparison axis and competes on feature surface + privacy label; concedes
  the premium without testing it.
- **Option B — hold the premium** ($9.99/$79, trial length TBD): defensible
  on surface area, but unvalidated; if the study's WTP metric comes in soft,
  repricing after launch is noisier than before.
- **Constraint that holds under either option:** **annual-first
  presentation.** The value proposition is explicitly longitudinal ("a year
  from now this will know you"); leading with a monthly plan is a positioning
  mismatch (§12.1). The paywall design assumes annual-first regardless of
  where `DEC-004` lands.

`DEC-004` **blocks** the paywall implementation and App Store Connect product
configuration — not this spec's other requirements (R3's integration contract,
R6's allowlist, R7's filings all proceed price-agnostically).

**Acceptance:** a decision record in this spec stating final monthly/annual
price, trial length, and rationale (including which option above was taken and
why), recorded **before** any App Store Connect product IDs are created or
paywall UI merges. Until then, no hardcoded price strings anywhere — the
paywall renders `Product.displayPrice` from StoreKit, never a literal.

### R2. Reduced-tier shipping posture — `DEC-001` OPEN
Does Memento ship on Reduced-tier devices (iOS 27, no Apple Intelligence) at
all, or declare a device requirement in the App Store listing? Source doc §4.1
recommendation: ship on Reduced tier, gated to free-forever capture-only with
**no paywall presentation** — recorded here as the recommendation, not the
decision:

- **Option A — ship on Reduced tier** (source doc recommendation): grows the
  funnel; the free tier (R4) is fully functional there (capture,
  transcription, timeline, keyword search, TTS, export are all
  non-generative). Implications: the paywall MUST consume spec 015 R7's
  `CapabilityTier` signal and be **structurally unpresentable** in
  `.reduced` — not "hidden by default" but unreachable, since selling AI
  reflection to a device that cannot generate it is a refund event *and* an
  App Review rejection risk (`REQ-PLAT-004`, `technology/10` §8's risk
  register); the App Store listing copy must describe generative features as
  requiring an Apple Intelligence device, honestly and up front.
- **Option B — declare an Apple Intelligence device requirement**: protects
  the brand (no degraded first impressions), shrinks the funnel.
  Implications: the paywall only ever renders in `.full`/`.local`, so
  `REQ-PLAT-004`'s Reduced-tier constraint becomes vacuous; the listing's
  device-requirement declaration becomes a store-metadata task (spec 002's
  lane) and must be verified to actually gate installs, not just warn.

**Holds under either option:** `REQ-PLAT-004` — the paywall MUST NOT be
presentable in the Reduced tier without a clearly disclosed feature list. Spec
015 R7 provides the resolved, observable `CapabilityTier`; this spec owns the
policy consuming it. Gating is evaluated at presentation time against the
*current* tier (015 R7 re-resolves on `SystemLanguageModel.availability`
change), never cached at launch.

**Acceptance (Given/When/Then):** Given `CapabilityTier == .reduced` (stubbed
per 015 R7's protocol seam), when any paywall entry point is exercised, then
no paywall is presented (Option A) or the app is not installable on such a
device at all (Option B) — the test asserts whichever branch `DEC-001`'s
recorded decision selects, and the decision record in this spec names the
option, the rationale, and the listing-copy consequence.

### R3. `REQ-MON-001` — StoreKit 2 + RevenueCat integration contract
StoreKit 2 is the purchase machinery; RevenueCat sits on top for receipt
validation and subscriber analytics. The data boundary is spec 014 R4's,
cited verbatim, not renegotiated: **RevenueCat is the sole allowed Z2
exception — it receives purchase events and an anonymous identifier only,
never content, never derived data, never user text, never custom attributes
that could carry content, and its calls are never `TrustZone`-tagged (they
carry no content for the enum to describe).** An agent adding "just a topic
tag for cohort analysis" to a RevenueCat attribute has committed a P0 privacy
violation (`REQ-PRIV-001`, `CONSTITUTION.md` §4 rule 8).

No-accounts consequences (spec 023, decided 2026-07-23):

- The RevenueCat **anonymous app-user ID is the only identifier that
  exists** — do not introduce any stable custom ID to "improve" attribution;
  the anonymity is the point, and it strengthens R5's "Data Not Collected"
  case.
- **Restore Purchases is the sole cross-device entitlement path** — there is
  no account to "log back into." It MUST be prominent in the paywall UI
  (visible without scrolling, one tap), not buried in Settings.
- App Review guideline 2.1's demo-account requirement is **moot** — nothing
  is sign-in gated — removing the mandatory reviewer-account chore spec 002
  had flagged.

Entitlement state is exposed as a single observable source of truth
(cached/offline-tolerant — StoreKit 2's local transaction state means a paid
user in airplane mode keeps paid features, preserving `REQ-PLAT-003`'s
offline loop; gating checks never require a network round-trip).

**Acceptance:**
- Given a StoreKit-test (sandbox/`.storekit` configuration) environment, when
  purchase and Restore Purchases are exercised, then entitlement state
  updates observably and survives relaunch offline — unit/UI tested.
- Given the RevenueCat integration's call sites, when spec 014 R4's
  `NetworkCallSiteAudit` runs, then every RevenueCat site classifies as the
  allowlisted Z2 exception and no call site passes custom attributes or any
  string derived from user content — a grep/lint over the integration module
  for the attribute-setting API surface backs the audit.
- Given the paywall UI, when it renders, then Restore Purchases is visible
  without scrolling — UI test.

### R4. `REQ-MON-003` — free/paid feature gating
The split, verbatim from §12.2 / `technology/10` §3:

| Free, forever | Paid |
|---|---|
| Unlimited capture | Weekly reflections |
| Transcription | Monthly insights / Patterns |
| Timeline | Ask (chat) |
| Search | Personal Voice |
| **Export (Markdown + JSON)** | |

**The principle: never hold a user's own words hostage.** The words are
theirs; the intelligence is the product. Export in particular MUST never be
paywalled — it is the structural guarantee behind the entire trust
proposition (and the preservation contract's PRES-085 export row).

This spec sets the *policy*; the surface specs (019, 018) implement the
gates. To keep that split honest, gating is one central check — entitlement
state (R3) × `CapabilityTier` (015 R7) — that surfaces query, never
per-surface bespoke logic that could drift.

**Two upsells exist in this app and they MUST never blend** (spec 017 R3,
`REQ-INT-008` — cited, not duplicated): Apple's PCC quota (where the app MAY
factually mention iCloud+ raises the limit, MUST NOT nag, and MUST NOT imply
Memento requires iCloud+) and Memento's own subscription paywall. A paid user
hitting the PCC quota is **not** a paywall moment — showing purchase UI to
someone who already paid, because Apple's quota ran out, is the exact
confusion this rule exists to prevent. Quota states render through spec 014
R2's component; the paywall renders only for unentitled users on paid-feature
entry points.

**Acceptance (Given/When/Then):**
- Given no purchase and no trial, when capture, transcription, timeline,
  search, and export are used, then every one completes with no paywall, no
  prompt, and no feature nag — the PRES-020…026 / PRES-085 surfaces stay
  reachable (Regression Guards below).
- Given no entitlement on a `.full`/`.local` device, when a paid surface
  (weekly/monthly/ask/Personal Voice) is opened, then the paywall presents.
- Given an active entitlement and an exhausted PCC quota, when a Z1 surface
  degrades per spec 017 R4, then the user sees 014 R2's degradation
  disclosure and **no purchase UI of any kind**.
- Given the export flow, when audited, then no code path can present a
  paywall — asserted structurally (export module has no dependency on the
  paywall/entitlement module), not just by test case.

### R5. `REQ-MON-004` — privacy label target: "Data Not Collected", verify first
Target label: **Data Not Collected**. This is contingent on 🔴 **V8** (source
doc §16 item 12, per the §16→V-queue numbering map): does RevenueCat's SDK
itself trigger a collection disclosure for purchase data? This is a
verify-first acceptance criterion, not an assumption in either direction —
the claim is currently 🔴 UNVERIFIED in `technology/10` §5 and MUST be
resolved against ground truth, not blog posts: inspect the RevenueCat SDK's
own bundled privacy manifest at the pinned SDK version, and confirm against
the aggregated privacy report App Store Connect derives from an archived
build with the SDK integrated.

**Priority ordering, decided in advance** (source doc §12.3, verbatim): if
RevenueCat forces a disclosure, evaluate StoreKit 2 direct and accept the
loss of subscriber analytics. **The label is worth more than the dashboard.**
Slate ships "Data Not Collected" and it is a meaningful part of why their
launch resonated; matching it removes a comparison axis Memento would
otherwise lose. This ordering means V8's answer changes R3's *mechanism*
(RevenueCat vs StoreKit 2 direct), never R5's *target*.

Corollaries:
- **No analytics SDK, at all.** Study telemetry is manually collected via
  surveys and interviews (`REQ-EVAL-005`) — slower, and the price of the
  label.
- `MeetMemento/PrivacyInfo.xcprivacy` currently declares User Content, Email,
  Name, and User ID — describing the Supabase backend being deleted, flagged
  stale in `CONSTITUTION.md` §2. It is rewritten by this spec **after** V8
  resolves (the verdict determines the final declaration), not before.

**Acceptance:** a written, sourced V8 verdict in this spec ("no disclosure
triggered — Data Not Collected confirmed" or "disclosure triggered —
StoreKit 2 direct evaluated, decision recorded"), mirrored to
`technology/11-verification-queue.md` V8; `PrivacyInfo.xcprivacy` matches the
verdict; App Store Connect's privacy section matches the `.xcprivacy` file;
the `CONSTITUTION.md` §2 stale flag is resolved, not left dangling.

### R6. `REQ-MON-005` — dependency allowlist as a checkable governance rule
The third-party dependency allowlist, verbatim from §12.4:

| Dependency | Justification | Reviewable |
|---|---|---|
| RevenueCat | Receipt validation, subscription state | Yes — see `REQ-MON-004` |
| *(nothing else)* | | |

Any addition requires an explicit decision record. The near-zero third-party
surface is a marketing asset and a security posture simultaneously — and per
spec 014 R3's lint-not-policy style, this MUST be a **CI check, not a
written rule someone can forget**:

- A committed allowlist file (e.g. `specs/dependency-allowlist.txt` or
  equivalent — implementer's choice of location, but versioned and
  greppable) lists the permitted third-party SPM package identities.
- A CI step diffs the resolved SPM dependency set (`Package.resolved` /
  `XCRemoteSwiftPackageReference` entries in `project.pbxproj`) against the
  allowlist; any package identity not on the list fails the build with a
  message pointing at `REQ-MON-005` and this spec — not a generic failure.
- Apple system frameworks are out of scope (the allowlist governs
  third-party packages); test-target-only tooling additions still count —
  the escape-hatch discipline of spec 017 R7 (a non-Apple model provider in
  test code only) is exactly the kind of thing this check must see and force
  a recorded decision for.
- **Sequencing note:** `supabase-swift` is still linked today and is in spec
  013 R7's deletion manifest (executed by spec 015). The lint lands with an
  allowlist reflecting the *target* state (RevenueCat only); wiring it into
  CI as a hard gate happens after spec 015's decommission removes the legacy
  dependency — before that it may run in report-only mode, but it MUST be a
  hard gate before this spec closes.

**Acceptance (Given/When/Then):** given a branch adding an SPM dependency not
on the allowlist, when CI runs, then the check fails naming `REQ-MON-005` —
demonstrated once with a throwaway fixture branch/package and recorded here.

### R7. `REQ-MON-002` — Small Business Program + PCC access, an operational requirement
SBP enrollment is **mandatory** — it is the eligibility condition for free
PCC inference, i.e. for the architecture itself, not merely a commission
perk. The eligibility chain (`technology/10` §1): SBP enrollment → <2M
first-time downloads → approved PCC access application → free PCC inference
→ ~100% gross margin, no server tier. Break any link and the economics
change.

**The filing process is already researched and documented — cite spec 013
R5(a)/(b), do not re-derive:** SBP is self-serve
(Account Holder, Paid Apps Agreement Schedule 2, Associated Developer
Accounts disclosure; Apple's pages disagree on timing — "five minutes" vs an
approval step with a 15-days-after-month-of-approval commission lag); PCC
access is a genuinely separate, gated request with **no stated lead time
anywhere in Apple's docs**. Both filings are recorded there as open user
actions (Account Holder login required). This spec's Task 4 is a
*confirmation* against 013's recorded filing dates, not a new filing.

**This is an ongoing operational requirement, not a one-time filing** (per
013 R5(b)'s research): crossing 2,000,000 first-time App Store downloads, or
letting SBP enrollment lapse (including by exceeding the $1M
prior-calendar-year proceeds cap — i.e. *success* ends eligibility), starts
a **6-month migration window** before PCC access is cut off. TestFlight/ad
hoc installs don't count against the threshold. This spec therefore owns a
standing contingency note, written before it's needed: monitor download
count and SBP status as release-checklist items; the offboarding options are
already spec'd elsewhere and are cited, not invented — pin all routing to Z0
(the spec 017 R2 `REQ-INT-004` override, degraded-but-honest per 014 R2) or
move to a paid provider through the spec 017 R7 `REQ-INT-015` escape hatch
(a product decision with privacy-label and copy consequences, `REQ-INT-016`).

**Acceptance:** this spec does not close until 013 R5's filing dates for (a)
and (b) are recorded; the offboarding contingency (trigger conditions,
6-month window, the two cited exit paths, and where download count/SBP
status get checked) is written into this spec's Current State or a linked
ops note — a future session facing the 2M threshold must find the plan
already made.

### R8. This spec's §16 verification-queue ownership
This spec owns source doc §16 **item 12 → V8** (RevenueCat SDK impact on the
"Data Not Collected" label) — currently **open/outstanding**. It is
unblocked by R5's ground-truth procedure: integrate (or at minimum resolve
and inspect) the pinned RevenueCat SDK, read its bundled privacy manifest,
and confirm against App Store Connect's aggregated privacy report on an
archived build — not closeable from documentation reading alone. No other
§16 items map here (item 5, the PCC filing, is spec 013 R5's — confirmed
against the §16 numbering map and `technology/11-verification-queue.md`).

**Acceptance:** V8's entry in `technology/11-verification-queue.md` is
updated (🔴 → ✅ with the verdict, or still-open with findings) before this
spec's status moves to done.

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
- [ ] `DEC-004` decision record exists in this spec (final price, trial
      length, option taken, rationale, annual-first presentation confirmed);
      no hardcoded price string literals in the paywall —
      `grep -rn '\$[0-9]' ` over the paywall module returns nothing (prices
      come from `Product.displayPrice`) (R1).
- [ ] `DEC-001` decision record exists; the tier-gating test passes for the
      recorded branch: with `CapabilityTier == .reduced` stubbed (spec 015
      R7's protocol seam), no paywall entry point presents purchase UI — or,
      if Option B was taken, the device-requirement declaration is verified
      in the App Store listing (R2, `REQ-PLAT-004`).
- [ ] StoreKit-test purchase and Restore Purchases flows pass; entitlement
      state survives relaunch in airplane mode; Restore Purchases is visible
      on the paywall without scrolling — UI test (R3).
- [ ] RevenueCat data-diet audit passes: no custom-attribute or
      content-derived-string call sites in the integration module (grep/lint),
      and spec 014 R4's `NetworkCallSiteAudit` classifies every RevenueCat
      call site as the allowlisted Z2 exception (R3, `REQ-PRIV-001`).
- [ ] Free-tier reachability walkthrough passes: capture, transcription,
      timeline, search, and export (Markdown + JSON) all complete with no
      purchase, no paywall, no prompt (PRES-020…026, PRES-085); the export
      module has no dependency on the paywall/entitlement module (R4).
- [ ] Quota/paywall separation test passes: an entitled user with exhausted
      PCC quota sees 014 R2's degradation disclosure and zero purchase UI;
      any iCloud+ mention follows spec 017 R3's `REQ-INT-008` rules — factual,
      no nagging, never implying Memento requires iCloud+ (R4).
- [ ] **Source doc §16 item 12 (→ V8): currently OUTSTANDING** — closed only
      by the ground-truth procedure: pinned RevenueCat SDK's bundled privacy
      manifest inspected + App Store Connect's aggregated privacy report on
      an archived build confirmed; verdict recorded in R5 and mirrored to
      `technology/11-verification-queue.md` V8 (🔴 → ✅ or still-open with
      findings) (R5, R8).
- [ ] **Confirmed target privacy label recorded**: "Data Not Collected", or
      the fallback (StoreKit 2 direct, subscriber analytics dropped) if V8
      shows RevenueCat forces a disclosure — the label wins over the
      dashboard per §12.3's priority ordering; `PrivacyInfo.xcprivacy`
      rewritten to match the verdict, App Store Connect privacy section
      matches the file, and `CONSTITUTION.md` §2's stale-`.xcprivacy` flag is
      resolved (R5).
- [ ] Dependency-allowlist CI check is wired as a hard gate (post-spec-015
      decommission of `supabase-swift`) and demonstrated: a fixture branch
      adding a non-allowlisted SPM package fails CI with a message naming
      `REQ-MON-005` and this spec (R6).
- [ ] SBP enrollment and PCC access request filing dates are recorded in spec
      013 R5 (still open user actions there as of 2026-07-24); the
      2M-download / SBP-lapse offboarding contingency note exists in this
      spec (trigger conditions, 6-month window, the two cited exit paths,
      where the counters get checked) (R7, `REQ-MON-002`).

## Regression Guards
`CONSTITUTION.md` §2 *Store compliance* flags `.xcprivacy` as stale pending this
spec — closing this spec must resolve that flag, not leave it dangling.
`REQ-PRIV-001` (spec 014, `CONSTITUTION.md` §4 rule 8) bounds what RevenueCat may
ever receive — content and derived data are never in scope for this integration.
Preservation contract: the paywall (ATTACH-07) gates only
reflections/patterns/ask/Personal Voice per `REQ-MON-003` — the free-tier
surfaces (capture, timeline, search, export; PRES-020…026, PRES-085's export
row) must remain reachable without any purchase or prompt.
