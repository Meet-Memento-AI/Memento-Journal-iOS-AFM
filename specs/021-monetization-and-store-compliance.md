---
id: 021
title: Monetization and Store Compliance
tier: P1
status: in-progress (2026-08-19) — DEC-001 = Reduced-tier capture-only no paywall; DEC-013 (2026-09-26) = Monetization Strategy: free chat with a daily limit, Day-0 offer (supersedes DEC-004's prices); DEC-014 (2026-09-26) = no free trial, the free tier is the trial; DEC-015 (2026-09-30) = $59.99/yr and $5.99/mo; RevenueCat switched on (2026-09-30); Support URL / privacy policy P0s closed in docs/app-store
effort: 2 sessions
depends_on: [017]
findings: [dec-004-pricing-open, dec-001-reduced-tier-open, revenuecat-z2-data-diet, privacy-label-verify-first, dependency-allowlist-ci-lint, sbp-pcc-eligibility-ops]
source_refs: [REQ-MON-001, REQ-MON-002, REQ-MON-003, REQ-MON-004, REQ-MON-005, REQ-MON-006, REQ-MON-007, REQ-MON-008, REQ-MON-009, DEC-001, DEC-004, DEC-013, DEC-014]
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

Existing monetization code (`withMemento/Views/.../Monetization`,
`SubscriptionPlan.swift` model) targets the current $9.99/mo /$79/yr plan against
the pre-2.0 backend; `withMemento/PrivacyInfo.xcprivacy` currently declares
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
**Resolved (DEC-013, DEC-014, DEC-015):** $59.99 a year, preselected, and
$5.99 a month (DEC-015, 2026-09-30). **No free trial:** the free tier is the trial.
Annual-first holds. See the two decision records and R10. The rest of this
section is kept as history.

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
  without scrolling — UI test (`PaywallUITests`, including at the largest
  accessibility text size).
- Given a selected plan, when the paywall renders, then the terms sit next to
  the purchase button (App Review 3.1.2): price and period, any free trial and
  what is charged after it, automatic renewal and where to cancel. Terms and
  Privacy links are one tap away. All of it is built from store data, never a
  literal (`PaywallPlan.disclosure`, `PaywallPlanTests`).

### R4. `REQ-MON-003` — free/paid feature gating
The split, verbatim from §12.2 / `technology/10` §3:

| Free, forever | Paid |
|---|---|
| Unlimited capture | Weekly reflections |
| Transcription | Monthly insights / Patterns |
| Timeline | Ask (chat) |
| Search | Personal Voice |
| **Export (Markdown + JSON)** | |

**Amendment (DEC-013, Monetization Strategy, 2026-09-26): the split
becomes the table below.** It replaces the table above. The principle
("never hold a user's own words hostage") and the one central gate are
unchanged.

| Free, forever | Pro (subscription) |
|---|---|
| Unlimited journaling: capture, transcription, timeline, search | Everything in Free |
| **Reading and exporting every entry. Never locked** | Ask across the **whole journal** ("memory across all entries") |
| Journaling Suggestions and the Day-0 prompt (053 R3) | Unlimited chats, kept in history, with a quiet fair-use limit |
| **One chat**, grounded in the **current entry and the current conversation**, with a **daily message limit** | Chat summaries (summarize-to-entry, PRES-046) |
| Clear the chat and start over, with nothing carried over | Weekly review (Sunday) |
| Entry reflections (019 R2, unchanged) | Monthly insights / Patterns |
| Read Aloud, the voice catalog, and Personal Voice (018, 033) | |

Where this departs from the strategy text, and why:
- **Personal Voice moves out of Paid.** 018 R8 (`REQ-VOX-003`) says
  "never a gate, never monetization bait". The old table contradicted it.
- **"Journal narrations" are not gated.** Read Aloud stays free (033: "no
  gating … none is added"). Narration Mode (028) is spoken chat, so it
  follows the chat rules.
- **No blurred insight previews on entries.** 019 R2 says the suppressed
  state has "no empty slot", and a blur would also reveal whether an
  observation exists.
- **No streaks.** Architecture NON-GOAL. Prompts are kept.

**Free chat rules (`REQ-MON-006`):**
- **Scope.** Free Ask is grounded in the entry it opened on plus the
  current conversation. It runs **no journal-wide retrieval**
  (`EntryRetriever` / `SearchJournalTool` stay Pro). Grounded-or-silent
  (`REQ-SUR-003`) still applies inside that scope. When a question needs the
  whole journal, the answer says honestly what it can see, and MAY add one
  inline line that Pro searches everything.
  **Opened from the Chat tab (2026-09-26):** there is no entry the chat
  "opened on", so the anchor is the **latest entry**.
  `ChatRetrievalScope.latestEntry` in `ChatService` scopes every retrieval
  path through `loadLocalEntries()`.
- **Daily limit.** The limit starts at about 10 user messages per local day.
  - It is **Memento's own entitlement limit**, counted on the device. It is
    **not** Apple's PCC quota, and the two MUST never blend: the limit copy
    never mentions Apple, iCloud+ or quota, and the PCC degradation copy never
    mentions Pro (see below, and 017 R3).
  - The value comes from RevenueCat offering metadata `free_daily_messages`,
    with a bundled default of 10, so R12 can test it without a release.
  - No running "N left" count. The limit is shown only when it is reached.
- **Safety comes first.** The limit is checked **after** the
  `SafetyClassifier` (026 R4). A crisis-adjacent message always gets the
  static card and is not counted.
- **One chat.** Starting a second chat is a re-offer moment (R9). After a
  downgrade, earlier chats stay readable but cannot be continued.
- **Pro fair use** is `REQ-INT-006`'s soft local limit. Reaching it degrades
  per 017 R4, **never** with purchase UI.

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
  **Amended (DEC-013):** paid surfaces are weekly, Patterns, whole-journal
  Ask, unlimited chats and summaries. Personal Voice is free. A free user
  opening Ask gets the free chat, not the paywall.
- Given a free user at the daily limit, when they send a crisis-adjacent
  message, then the resource card shows and the limit does not block it.
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
- `withMemento/PrivacyInfo.xcprivacy` currently declares User Content, Email,
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
| Neural TTS integration surface (spec 030) | The one voice engine the product controls; fully local, zero network egress at synthesis, model-load, or voice-selection time (`REQ-TTS-001`) | Yes — see spec 030 and `018` R12 |
| *(nothing else)* | | |

**Added 2026-08-18 — two things this table cannot see, and one it must not be
asked to.** (a) **Model weights are not a package.** The neural voice ships
weights whose integrity is governed by spec 030's compiled-in SHA-256 manifest
(`REQ-TTS-002`) and whose licensing is governed by `018` R12 (`REQ-TTS-009`) —
*not* by this table, because the CI check below reads SPM package identities and
would wave a 200 MB model through without noticing it. The allowlist file
records them under a separate banner so the gap is visible rather than silent.
(b) **License class is not justification.** This table's second column asks *why*
a dependency exists; it has never asked *under what license*, which was safe
while the answer was uniformly permissive. It no longer is: the weights carry an
attribution condition and use-based restrictions. That is tracked in `018` R12
rather than by widening this table, so there stays exactly one place that
adjudicates TTS licensing.

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

> **Partial — landed 2026-08-02:** the allowlist file
> (`specs/dependency-allowlist.txt`, target = RevenueCat only) and the CI check
> (`scripts/ci/check_dependency_allowlist.sh`, `.github/workflows/spec-gates.yml`)
> are implemented. Per this R6's sequencing note it runs **report-only**
> (`ALLOWLIST_ENFORCE=0`): it currently reports three off-allowlist packages
> (`supabase/supabase-swift` — removed by spec 015; `dominikmartn/progressiveblurheader`
> and `svgkit/svgkit` — need a REQ-MON-005 decision record or removal).
> Verified: `ALLOWLIST_ENFORCE=1` fails on the current tree, confirming the
> gate works. Flip to enforcing after spec 015's decommission — must be a hard
> gate before this spec closes.

> **Amended 2026-08-18 (spec 030) — adding a dependency to a report-only gate is
> a governance regression, and this is the decision record saying so out loud.**
> The neural-voice integration surface is the first *new* third-party package
> admitted since this rule was written, and it would land while the check still
> runs with `ALLOWLIST_ENFORCE=0`. Report-only means the allowlist would be
> documenting the addition rather than governing it.
>
> **Re-verified 2026-08-18 — the cost of fixing this has collapsed.** The partial
> note above lists three off-allowlist packages. Only **one** remains:
> `grep -oE 'repositoryURL = "[^"]+"' withMemento.xcodeproj/project.pbxproj`
> now returns `SVGKit/SVGKit` alone. `supabase/supabase-swift` went with spec
> 015's decommission and `dominikmartn/progressiveblurheader` is gone too —
> neither this spec nor `ROADMAP.md` records when. Update this partial note when
> R6 is next worked.
>
> **Requirement:** spec 030 MUST NOT link its dependency while the gate is
> report-only. Either enforcement is flipped on first — which now means resolving
> or removing exactly one UI package — or spec 030 is blocked. This is a
> deliberate ordering constraint, not a nice-to-have: the whole value of
> `REQ-MON-005` is that the *first* unreviewed package is the one it catches, and
> a gate that has been off long enough to accumulate exceptions is a gate nobody
> believes. One SVG renderer in an on-device-only journal is a cheaper thing to
> resolve than the precedent of skipping this.

> **RESOLVED 2026-08-18 — the gate is ENFORCING and the third-party SPM set is
> empty.** `svgkit/svgkit` was not granted a `REQ-MON-005` record; it was
> **removed**, because inspection showed it was never actually a dependency in
> any meaningful sense: declared as an `XCRemoteSwiftPackageReference` but with
> `packageProductDependencies = ()` empty, **zero** `XCSwiftPackageProductDependency`
> entries, and no `import SVGKit` in any Swift file. The SVGs in
> `Assets.xcassets` are rendered by Xcode's native asset-catalog support. Its
> transitive pins, `cocoalumberjack` and `swift-log`, went with it, and
> `Package.resolved` was deleted because no packages remain.
>
> Evidence: `** BUILD SUCCEEDED **` on the iPhone 17 simulator after removal;
> `ALLOWLIST_ENFORCE=1 scripts/ci/check_dependency_allowlist.sh` exits 0 with an
> empty resolved set; the gate was re-proven against a planted `Alamofire`
> reference, failing with exit 1 and naming `REQ-MON-005`.
> `.github/workflows/spec-gates.yml` now sets `ALLOWLIST_ENFORCE: "1"` and the
> job name has dropped its `[report-only]` suffix.
>
> **This closes spec 030's ordering constraint** — the neural-voice dependency
> may now be added. It also means R6's own "must be a hard gate before this spec
> closes" condition is met, and the 2026-08-02 partial note above is superseded
> in full: its three named packages are all gone.

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

### R9. `REQ-MON-007` — re-offer moments (DEC-013)
Pro is offered on Day 0 (053 R5) and again **only where the user
reaches for something Pro does**. This keeps the ProGate rule "opened by
the user, never pushed at them on entry" (017 R3 "never nag").

| # | Moment | What shows | RevenueCat placement |
|---|---|---|---|
| 1 | Tries to start a second chat | The offer | `second_chat` |
| 2 | Hits the free daily message limit | Inline limit note, with one tap to the offer | `daily_limit` |
| 3 | Clears the chat | A confirmation: "Start over?", with **Start over** or **Keep it with Pro** | `clear_chat` |
| 4 | Taps chat summary | The offer | `chat_summary` |
| 5 | First Sunday: taps the weekly review card | A **locked card** with one teaser line computed in Swift from `InsightEngine` facts (for example, "You wrote 5 entries this week"). **No model generation for free users, and no weekly-ready notification** for locked content (019 R8). | `weekly_review` |
| 6 | Opens any other locked Pro surface (Patterns, whole-journal Ask) | The existing `.proGated` card and offer | `locked_surface` |
| — | Day 0 | The onboarding paywall (053 R5) | `onboarding` |

**Not adopted** (governance): the 5th-entry moment, which is an unprompted
offer not tied to a paid feature; the 7-day streak (NON-GOAL); and blurred
insight previews (019 R2).

Rules:
- **At most one full-screen offer per local day**, the Day-0 paywall
  included. After that, a moment shows its inline form instead: the
  `ProOfferCard` style, or the inline note for moment 2.
- **Every offer is the same straight offer:** the plans at their store
  price. There is no trial (DEC-014).
- **The one-a-day cap applies to offers the app raises on its own.** An
  offer the person opens by tapping is never held back, whether from the
  free chat's **Upgrade** pill (placement `locked_surface`), a lock card, the
  reset dialog's **Keep it with Pro**, or the daily-limit note's
  **Upgrade** (2026-09-26).
- **Never** on a `.reduced` device (R2), **never** straight after a crisis
  card (019 R7), and **never** on any PCC quota state (R4).

**Acceptance:**
- Given two moments on one day, then the second is inline.
- Given any offer, then no copy mentions a trial
  (`PaywallPlanTests.testNoCopyPromisesATrial`).
- Given each moment, then its purchase carries the placement in the table
  (the RevenueCat `presentedOfferingContext`).

### R10. `REQ-MON-008` — paywall structure and copy (DEC-013, amended by DEC-014)
**There is no free trial (DEC-014, 2026-09-26).** The free tier is the
trial: journaling and a daily chat work fully without Pro, so the paywall is
a straight conversion.

**Two presentations of `PaywallView`:**
1. **Onboarding (053 R5): two pages.**
   - **What you get:** memory and insights first. Ask across your journal,
     the weekly review, Patterns, chat summaries.
   - **Plans:** Annual preselected, with Monthly beside it.
   - **Primary:** the subscribe button (below). **Secondary:** **Continue
     free**, a clearly visible action, not fine print.
2. **Re-offer (R9): one screen.** The Free / Pro comparison table plus the
   plans.

**Copy** (`PaywallTrigger` in `PaywallPlan.swift`, 2026-09-26):
- **The headline follows the entry point and the journal.** It's short and
  declarative, ends in a full stop or a question mark, and **never shows a
  number**. Entry counts and the day (`PaywallContext`, local and
  content-free) only choose the phrase that is true right now.

  | Opened from | Headline | Description |
  |---|---|---|
  | Settings | Your journal, remembered. | Pro brings memory to every entry. Your writing stays free. |
  | Onboarding | This is just the beginning. | Pro remembers every entry. Journaling stays free. |
  | Chat Upgrade pill, 2+ entries | Every entry. One conversation. | Free chat sees your latest entry. Pro sees them all. |
  | Chat Upgrade pill, 0–1 entries | A chat that remembers. | As you write, Pro remembers every entry. |
  | Second chat | More to talk about. | Pro gives you unlimited chats. |
  | Daily limit | More to say? | Your messages return tomorrow. Or go unlimited with Pro. |
  | Reset | Worth keeping. | Pro saves every conversation. |
  | Chat summary | From chat to journal. | Pro turns your conversations into entries. |
  | Weekly, 2+ entries this week | Your week, in focus. | Pro turns this week's writing into today's / a Sunday recap. |
  | Weekly, quiet week | One week at a time. | Pro writes a short recap of your week, today / every Sunday. |
  | Patterns, 10+ entries | See what repeats. | Pro finds the people, places and moods that return. |
  | Patterns, fewer | Patterns take time. | Keep writing. Pro will show you what repeats. |

- **The lock cards on Weekly and Patterns** use the same headline and
  description as the paywall they open, with an **Upgrade** button.
- **Primary button:** frames Pro as an upgrade and names exactly what is
  charged and how often, from the store: "Upgrade for $59.99 a year" /
  "Upgrade for $5.99 a month".
- **Terms line:** "Auto-renews yearly. Cancel anytime." (or monthly).
- **Enforced by `PaywallPlanTests`,** across 200+ journal states:
  - no trial
  - no digits in any headline or description
  - headlines are complete lines, at most 30 characters
  - descriptions are at most 60 characters
  - no two entry points share a headline

**Plan picker.** DEC-013 banned toggles because Monthly had no trial, so a
Yearly / Monthly toggle turned a trial on and off, which reads as the
free-trial toggle pattern Apple rejects. **With no trial on either plan,
that reason is gone.** The toggle only switches the billing period, so the
billing pill (`PaywallBillingToggle`) is allowed again.

**Dropped with the trial:** the timeline page, the day-25 reminder card,
and the cancel-during-trial win-back offer.

### R11. `REQ-MON-009` — measuring without analytics (DEC-013)
The strategy's metrics come from **server-side sources that already exist**:
- RevenueCat, under the anonymous app-user ID (R3). Placements and
  Experiments are allowed.
- App Store Connect (installs, conversion, proceeds, refunds).
- The Apple Search Ads console.

No new client events are added.

| Metric | Source |
|---|---|
| **Revenue per install at day 60** (main metric) | RevenueCat revenue for a first-seen cohort ÷ App Store Connect first-time downloads in the same window |
| Day-0 conversion rate | RevenueCat purchases on the first-seen day ÷ new customers (DEC-014: there is no trial to start) |
| Free-to-paid | RevenueCat purchases by first-seen cohort over time |
| Re-offer conversion | RevenueCat purchases grouped by placement (R9) |
| Refund rate | App Store Connect / RevenueCat refunds. Budget **3–5% of revenue** |
| AI cost per user | **Not measured.** Inference is on-device or Apple PCC at about zero marginal cost (R7, `REQ-MON-002`). The free limit and fair use are tuned for conversion and PCC headroom, not margin |

**Forbidden:**
- analytics SDKs, custom RevenueCat attributes, and email
- the AdServices attribution token
- any per-user event log leaving the device

These follow `REQ-MON-004`, `REQ-EVAL-005` and spec 023.

**Apple Search Ads** runs on the keywords "ai journal" and "rosebud
alternative", measured in the Search Ads console only. The store metadata
still never names competitors (`docs/app-store/04`).

**Unit economics** after the 15% Small Business rate: an annual subscriber
brings in about $4.25 a month, a monthly subscriber about $5.09 (DEC-015,
$5.99 × 0.85).

**Billing:**
- Turn on App Store Connect's **Billing Grace Period**; billing retry is
  automatic on iOS.
- The strategy's Android items don't apply: Android is an architecture
  NON-GOAL.

### R12. Tests and when to change (DEC-013)
One test at a time, **run as RevenueCat Experiments at the offering level**,
never client-side:
1. ~~Trial length: 7 vs 30 days on annual.~~ **Dropped with the trial
   (DEC-014).** Testing any trial again needs its own decision record.
2. Free daily message limit: the `free_daily_messages` offering metadata.
3. First-chat placement and length: the `first_chat_mode` offering metadata,
   read by 053 R4, with a bundled default.
4. ~~Monthly at $9.99 vs $7.99.~~ Settled at $5.99 by DEC-015. Any other
   monthly price test needs its own decision record.
5. A $99.99 lifetime plan offered only to people who decline or cancel.
   **This needs its own decision record first**, because it reverses the
   2026-09-26 "no lifetime" decision, and `PaywallPlan.ordered` ignores
   lifetime packages today.

**When to change:** the strategy planned to shorten the trial once installs
are paid for. With no trial (DEC-014), the question for paid acquisition
becomes whether the free tier converts fast enough to pay back ad spend.
Reintroducing a trial for that reason needs a decision record that reverses
DEC-014.

## Out of Scope

- Which specific surfaces are gated behind the paywall beyond the free/paid split
  in `REQ-MON-003` — that's each surface spec's (019, 018) concern to implement;
  this spec sets the policy.
- **App Store Connect metadata mechanics beyond the privacy label** — owned by
  **`docs/app-store/`** (added 2026-08-07), which supersedes spec 002's
  store-facing scope. The split, so the privacy label has exactly one owner:
  - **This spec owns the *decision*** — `REQ-MON-004`'s "Data Not Collected"
    target and the ⚠️ V8 verification (does RevenueCat's SDK force a collection
    disclosure?), including §12.3's priority ordering that the label beats the
    dashboard.
  - **`docs/app-store/03-privacy-labels-and-manifest.md` owns the *execution***
    — the `PrivacyInfo.xcprivacy` target state, the App Store Connect form, and
    the standing rule that the manifest, the label, and the published privacy
    policy must always agree. It cites R5; it does not re-decide it.
  - Two things it already did, both agent-side and verified: removed the
    unjustified `NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`)
    declaration — no boot-time API is called anywhere — and landed
    `scripts/ci/check_privacy_manifest.sh`, which fails on both an
    under-declared and an over-declared required-reason API, plus on any
    regression of `NSPrivacyTracking` or the empty
    `NSPrivacyCollectedDataTypes`. R5's remaining work is V8 and the label
    itself.
  - R6's dependency allowlist gains a store consequence recorded in
    `docs/app-store/03` §3: **RevenueCat is on Apple's list of SDKs requiring a
    bundled privacy manifest *and* a signature**, so landing it adds an upload
    obligation (`ITMS-91061`) on top of the V8 label question.

## Decision record — RevenueCat integration (2026-09-24)

- **V8 verdict (R5): disclosure triggered.** The bundled manifest of
  purchases-ios-spm 5.91.0 (`Sources/PrivacyInfo.xcprivacy`) declares
  `NSPrivacyCollectedDataTypePurchaseHistory`: Linked = false,
  Tracking = false, purpose App Functionality.
  - **Product owner's decision: keep RevenueCat anyway.** This overrides R5's
    "StoreKit 2 direct" fallback.
  - The label target is now **Purchases → Purchase History, not linked to
    the user**, alongside the spec 042 feedback types the manifest already
    declared.
  - `PrivacyInfo.xcprivacy` mirrors the declaration, and
    `check_privacy_manifest.sh` enforces the pairing.
  - Still open: confirming against App Store Connect's aggregated report on
    an archived build.
- **Products:** `monthly` and `yearly`, both granting entitlement
  `memento_ai_pro`. The non-consumable `lifetime` was dropped on 2026-09-26
  (product owner's call): Memento Pro is a subscription only, and the paywall
  ignores a lifetime package even if an offering carries one.
  - Prices come only from the store. The paywall draws the current
    offering annual-first (see *Paywall UI* below).
  - Setup steps: `docs/app-store/revenuecat-setup.md`.
- **Integration (R3):**
  - `Services/Purchases/EntitlementStore` is the single observable source.
    It uses the anonymous ID only and has no `logIn` or attributes, which
    `RevenueCatConfigTests` enforces.
  - The last known state is cached so gates work offline.
  - Restore Purchases is in the paywall template and in Settings.
- **Gating (R4):** `ProAccess.decide` is the one gate. It is applied through
  `.proGated(_:)` inside `WeeklyReflectionView`, `PatternsView`, and on
  `AIChatView`.
  - It never looks at quota.
  - Ineligible devices never see purchase UI (R2, `ProAccessTests`).
  - Personal Voice has no user-facing surface yet. Gate it through the same
    call once it has one.
  - Export and the other free surfaces do not import the module.
- **Switched off (2026-09-25):** product owner's call, pending the paywall
  design fixes and `DEC-004`. `RevenueCatConfig.isPaywallEnabled = false`
  skips `Purchases.configure`, so every paid surface is open and Settings
  has no Pro section. The integration stays in place. Setting the flag to
  `true` turns it back on.
- **Switched on (2026-09-30):** product owner's call, for live testing.
  `isPaywallEnabled = true`.
  - Debug builds run against RevenueCat's Test Store (`test_` key).
  - Release builds need the `appl_` key in `RevenueCat.release.xcconfig`,
    or Pro fails open.
  - DEBUG-only launch arguments: `-EnablePaywall` / `-DisablePaywall`
    override the switch per launch. UI tests that measure the full chat pass
    `-DisablePaywall`. `-ForceFreeTier` shows the free chat.
  - The go-live checklist in `docs/app-store/revenuecat-setup.md` still
    applies before any App Store submission.
- **Paywall UI (2026-09-26): the app draws its own.** `PaywallView`
  (`Views/Purchases/`) renders the current offering from `EntitlementStore`.
  It replaces RevenueCatUI's template, whose copy contradicted R4 and which
  had no dark mode and broke at large text sizes.
  - RevenueCatUI is kept only for the Customer Center.
  - The plan and copy rules live in `PaywallPlan`. (Trial eligibility was
    removed with the trial, DEC-014.)
  - `PaywallPlanTests.testNoPriceLiteralsInThePaywallModule` runs R1's check
    against string literals only. The raw `grep '\$[0-9]'` also matches
    Swift's `$0` closure shorthand, so it can't return nothing.
  - A DEBUG-only harness (`-UITesting -PaywallPreview`) presents it over
    `TestStoreProduct` data without configuring the SDK. This is how it is
    reviewed and UI-tested while the switch is off.

## Decision record — `DEC-004` pricing (2026-09-26)

> **Superseded the same day by DEC-013** (below): $9.99 a month with no
> trial, and $59.99 a year with a 30-day trial. Kept for history.

- **Prices: $5.99 a month and $59.99 a year**, set by the product owner.
  Other storefronts use Apple's equivalent price points.
  - This is below the reference competitor Slate ($7.99 / $59.99) on
    monthly and matches it on annual. It is close to R1's Option A (match
    Slate), with a cheaper monthly plan.
  - The annual plan saves about 16% against twelve monthly payments. The
    paywall computes that figure from store prices and rounds it down.
  - Annual-first presentation holds (R1).
- **No lifetime purchase.** See the RevenueCat decision record above.
- **Still open: trial length.** The paywall shows whatever free
  introductory offer App Store Connect carries, and only to eligible
  accounts. The DEBUG preview data uses 14 days as a placeholder.
- The prices live in App Store Connect and in RevenueCat's Test Store, never
  in code (R1). Setup: `docs/app-store/revenuecat-setup.md`.

## Decision record — `DEC-013` Monetization Strategy (2026-09-26)

The product owner adopted the **Memento Monetization Strategy (September
2026)**: "Journaling in Memento is free forever. The AI is what people pay
for." The trial is offered on Day 0, right after Memento responds to the
user's first entry.

The strategy is applied **within the specs' governance**. The owner decided
that privacy and the architecture NON-GOALs rule where they conflict, and
that growth is simplified to fit.

| Strategy item | Where it lives | How it's applied |
|---|---|---|
| Day-0 quiz, first entry, first chat, paywall, reminder, widget | **053** (new) | Adopted. Contract amended (PRES-061/063, 023 R3, 038) |
| Annual $59.99 with 30-day trial, preselected; Monthly $9.99 with no trial | R1, R10 | Adopted. **Supersedes DEC-004's $5.99 monthly** |
| No weekly plan, no lifetime | R10, R12 | Adopted. Lifetime appears only as a gated test |
| Free / paid table | R4 | Adopted, except narrations, Personal Voice, blurred previews and streaks (reasons in R4) |
| Free chat: one chat, daily limit, current entry and chat only | R4, 019 R5, 017 R3 | Adopted. The limit never blends with Apple's quota and never blocks safety |
| Re-offer moments | R9 | Adopted for the six moments that start from a Pro feature. 5th entry and 7-day streak dropped |
| At most one full-screen offer a day; trial until used | R9 | Adopted |
| No toggle paywall | R10 | Adopted. Also replaces the 2026-09-26 billing pill |
| Day-25 reminder by notification and email | R10 | **Adapted:** in-app card only. No third notification (019 R8), and no email (023) |
| Discount when cancelling during the trial | R10 | Adopted as an App Store win-back offer |
| Server-side subscription tracking | R3, R11 | Already true (RevenueCat, anonymous ID) |
| Android grace period and retry | R11 | Not applicable (NON-GOAL). Billing Grace Period turned on for iOS |
| Refund budget, unit economics | R11 | Recorded |
| AI cost per user | R11 | **Dropped:** about zero cost; tuning is for conversion |
| Shareable insight cards | — | **Dropped:** NON-GOAL "sharing". Growth relies on the widget, Search Ads, privacy-first positioning and word of mouth |
| Apple Search Ads | R11 | Adopted, without attribution SDKs |
| No clinical claims, privacy up front | 002, `docs/app-store/04` | Already true |
| Metrics | R11 | Adopted from RevenueCat, App Store Connect and Search Ads only |
| Test roadmap, when to change | R12 | Adopted as RevenueCat Experiments; lifetime test needs a decision first |

> **Amended the same day by DEC-014** (below): no free trial. The rows on
> the 30-day trial, "trial until used", the day-25 reminder and the
> cancel-during-trial discount no longer apply, and the toggle ban is lifted.

## Decision record — `DEC-014` No free trial (2026-09-26)

The product owner removed the free trial: **the free tier is the trial.**
Journaling, reading, export and a daily chat work fully without Pro, so
the paywall is a straight conversion that says exactly what is charged.

- **Prices unchanged:** $59.99 a year (preselected) and $9.99 a month.
  **No introductory offer on either product.**
- **Copy** (R10): no copy mentions a trial, and a test enforces it. The
  terms line is "Auto-renews yearly. Cancel anytime." (The title and button
  have since moved on: see R10's copy table and "Upgrade for {price}".)
- **Dropped from DEC-013:**
  - the 30-day trial, and "trial until used" (R9)
  - the onboarding timeline page and the "Start your 30 days of Memento"
    title (R10, 053 R5)
  - the day-25 in-app reminder card (R10)
  - the cancel-during-trial win-back offer (R10)
  - the trial-length test and the plan to shorten the trial later (R12)
- **Toggle ban lifted** (R10). DEC-013 banned toggles only because Monthly
  had no trial, so the toggle turned a trial on and off. With no trial on
  either plan, the Yearly / Monthly pill only changes the billing period.
- **Code:** trial eligibility (`EntitlementStore.trialEligibleProductIDs`,
  `PaywallModel.isTrialEligible`) and every trial string were removed from
  `Views/Purchases/`.

## Decision record — `DEC-015` monthly price (2026-09-30)

- **Prices: $59.99 a year (preselected) and $5.99 a month**, set by the
  product owner. This replaces DEC-013's $9.99 monthly. No free trial
  (DEC-014).
- **The annual plan saves 16%** against twelve monthly payments ($71.88).
  The paywall computes this from store prices and rounds it down, so the
  chip reads "Save 16%".
- **Where the prices live:** App Store Connect (production) and RevenueCat's
  Test Store products (Debug). The app never contains a price (R1).

## Tasks
- [x] 1. Resolve `DEC-004`: superseded by DEC-013 and DEC-014 (2026-09-26). $59.99/yr and $9.99/mo, no free trial.
- [ ] 2. Resolve `DEC-001` (Reduced-tier shipping posture).
- [x] 3. Implement StoreKit 2 + RevenueCat per `REQ-MON-001` (2026-09-24; see decision record).
- [ ] 4. Confirm Small Business Program enrollment status against spec 013's
      filing (`REQ-MON-002`).
- [ ] 5. Implement free/paid feature gating (`REQ-MON-003`).
- [ ] 6. ⚠️ VERIFY item 12: RevenueCat SDK vs. "Data Not Collected" label;
      update `PrivacyInfo.xcprivacy` accordingly (`REQ-MON-004`).
- [ ] 7. Document the dependency allowlist governance process (`REQ-MON-005`).
- [ ] 8. `PaywallView` to R10:
      - [ ] the two-page onboarding presentation with **Continue free**
      - [x] the one-screen re-offer, with the billing pill (allowed again, DEC-014)
      - [x] copy per R10 and preview data at $9.99 / $59.99 with no trial (2026-09-26)
- [x] 9. Free chat scope and daily limit (R4 `REQ-MON-006`; 019 R5 and 017 R3
      amendments). The limit comes after the safety classifier. (2026-09-26:
      the free chat from Figma 1177:3147 — `ChatTier`, `FreeChatAllowance`,
      `ChatRetrievalScope`, `UpgradePill`, reset dialog, `DailyLimitNote`;
      `FreeChatTests`, `FreeChatUITests`.)
- [ ] 10. Re-offer moments with the once-a-day cap and RevenueCat placements
      (R9). **Done (2026-09-26):** moments 2 (daily limit) and 3 (reset), and
      the free chat's Upgrade pill. **Open:** moments 1 and 4 have no entry
      point yet (the free header has no history or summary), moment 5 (weekly
      card), the cap for app-raised offers, and passing each trigger's
      placement to RevenueCat.
- ~~11. Day-25 in-app trial card and the win-back offer (R10).~~ Dropped with the trial (DEC-014).
- [ ] 12. App Store Connect:
      - `yearly` 59.99 USD and `monthly` 9.99 USD, **no introductory offer on either**
      - Billing Grace Period on
      - mirror the prices in RevenueCat's Test Store
- [ ] 13. Day-0 onboarding: spec 053.

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
