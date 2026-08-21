---
id: 017
title: Intelligence Boundary and Prompt Architecture
tier: P0
status: in-progress (2026-08-19) — Ask pipeline shipping (`ask@10`); `[Turn:]` is stance guidance; DEC-003 = bundled prompts only; provider-swap seam is `IntelligenceService`
effort: 3 sessions
depends_on: [014, 015, 016]
findings: [single-importer-boundary, table-driven-router-with-reasoning-column, quota-governor-reactive-first, degradation-prompt-variants, provider-swap-seam, prompt-registry-dec-003-open]
source_refs: [REQ-INT-001, REQ-INT-002, REQ-INT-003, REQ-INT-004, REQ-INT-005, REQ-INT-006, REQ-INT-007, REQ-INT-008, REQ-INT-009, REQ-INT-010, REQ-INT-011, REQ-INT-012, REQ-INT-013, REQ-INT-014, REQ-INT-015, REQ-INT-016, REQ-PRM-001, REQ-PRM-002, REQ-PRM-003, REQ-PRM-004, REQ-PRM-005, DEC-003]
tech_refs: [technology/01-foundation-models.md, technology/02-private-cloud-compute.md, technology/04-evaluations.md]
---

# 017 — Intelligence Boundary and Prompt Architecture

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§7 "Intelligence layer" and §11 "Prompt architecture" in full (prompt architecture
folded into this spec rather than split out — `PromptRegistry` is one component of
`IntelligenceService`, not a separate subsystem).

## Why

This is P3 made concrete: exactly one Swift module imports `FoundationModels`;
everything else — entry reflection, weekly/monthly synthesis, ask/chat — calls the
`IntelligenceService` protocol. Model choice, Z0/Z1 routing, PCC quota governance,
and degradation all live here, which is what makes provider swapping
(`REQ-INT-015`) a construction-site change instead of a rewrite. Also absorbs the
one deliberate capability regression of the rewrite: losing Supabase's DB-backed
`prompts` table with hot-reloadable versioning (§11.1) — replaced by bundled,
versioned Markdown prompts with an optional signed remote manifest.

## Technology References

- `specs/reference/technology/01-foundation-models.md` — primary:
  `LanguageModelSession`, `@Generable`/`@Guide`, the `LanguageModel` protocol
  (provider-swap seam for `REQ-INT-015`), `Tool`/`SpotlightSearchTool`,
  Dynamic Profiles, context sizes (4096/8192 on-device).
- `specs/reference/technology/02-private-cloud-compute.md` —
  `PrivateCloudComputeLanguageModel`, reasoning levels, `quotaUsage`, and the
  routing table/`QuotaGovernor` this spec builds.
- `specs/reference/technology/04-evaluations.md` — `REQ-PRM-004` prompt
  version traceability and the `Evaluations` framework this spec's outputs
  feed into (spec 022).

## Current State (evidence)

No direct Gemini SDK/HTTP calls exist in Swift — all LLM calls currently happen
server-side in Deno edge functions, called via `ChatService.swift`
(`MeetMemento/Services/ChatService.swift`) and `InsightsService.swift`. No
`IntelligenceService`-shaped protocol, no `@Generable`/guided generation, no
prompt registry exists client-side; prompt "versioning" today is an informally
synced Markdown file (`supabase/functions/chat/MEMENTO_SYSTEM_PROMPT.md` +
`docs/prompts/`), not a system.

## Requirements

**Traceability:** R1 → `REQ-INT-001`, `REQ-INT-002`; R2 → `REQ-INT-003`,
`REQ-INT-004`; R3 → `REQ-INT-005`–`008`; R4 → `REQ-INT-009`–`011`; R5 →
`REQ-INT-012`, `REQ-INT-013`; R6 → `REQ-INT-014`; R7 → `REQ-INT-015`,
`REQ-INT-016`; R8 → `REQ-PRM-001`–`005`, `DEC-003` (OPEN); R9 → context-budget
and session-architecture contracts supporting R1/R2; R10 → source doc §16
items 4 and 14. Zone semantics and the disclosure UI are **not** redefined
here: spec 014 R1 owns the `TrustZone`/`PCCReasoningLevel` contract and
014 R2 owns the zone-at-point-of-use component and canonical degradation
copy. This spec decides *which* zone/reasoning level each intent gets (R2)
and *implements* the degradation 014 R2 promises the user (R4).

### R1. `IntelligenceService` protocol and the single-importer boundary
Exactly one Swift module imports `FoundationModels` (`REQ-INT-001`, P3,
`CONSTITUTION.md` §4 rule 5). Everything else — capture, surfaces, voice,
evaluations — depends on this protocol, taken verbatim from source doc §7.1
(do not redesign it):

```swift
protocol IntelligenceService: Sendable {
    func reflect(on entry: Entry) async throws -> EntryReflection
    func weeklyReflection(for week: DateInterval) async throws -> PeriodReflection
    func monthlyInsight(for month: DateInterval) async throws -> PeriodReflection
    func ask(_ question: String,
             in conversation: Conversation) -> AsyncThrowingStream<AnswerChunk, Error>
    func availability() async -> IntelligenceAvailability
}

struct GenerationRequest: Sendable {
    let intent: GenerationIntent      // .entryReflection, .weekly, .monthly, .ask, .title
    let zone: TrustZone               // spec 014 R1's enum — set BEFORE the call
    let allowsDegradation: Bool
    let promptVersion: String
    let toolsEnabled: Bool
}

struct GenerationOutcome<T: Sendable>: Sendable {
    let value: T
    let zoneUsed: TrustZone           // the zone it ACTUALLY ran in (REQ-INT-002)
    let modelIdentifier: String
    let wasDegraded: Bool
    let latency: Duration
}
```

One deliberate reconciliation against the source doc: §7.1 sketches a
two-case `enum TrustZone { case device, apple }`, but spec 014 R1 has since
defined the canonical contract (`.z0Device` / `.z1AppleContent(reasoningLevel:)`
/ `.z1AppleContentFree`, plus `PCCReasoningLevel`). This spec adopts 014's
enum — which also means the reasoning level rides on the zone value rather
than being a separate request field, so R2's router emits one value that
answers both "where" and "how hard." `preferredZone` is renamed `zone` to
match 014 R1's "set before the call, never inferred after" rule. Every
method returns the zone actually used and callers MUST surface it
(`REQ-INT-002`) — there is no API shape in which a caller can be unaware of
where generation happened.

**Acceptance:**
- `grep -rl --include='*.swift' 'import FoundationModels' MeetMemento MeetMementoTests MeetMementoUITests | wc -l` returns exactly **1**, and that
  one file is in the intelligence module. This exact check runs in CI as a
  lint step (satisfying the Regression Guards' "checkable by build
  configuration, not just code review" demand — the grep is the checkable
  floor; if target-level framework linking can additionally enforce it,
  do both).
  > **Partial — landed 2026-08-02:** the CI grep is implemented and wired
  > (`scripts/ci/check_single_intelligence_importer.sh`,
  > `.github/workflows/spec-gates.yml`), enforcing `count ≤ 1` and green on the
  > current tree (0 importers; `#if canImport` guards correctly excluded). Set
  > `INTELLIGENCE_IMPORTER_EXPECT_EXACTLY=1` once the `IntelligenceService`
  > module lands to also catch accidental removal. The protocol/type
  > implementation (bullets below) is still pending the Swift work.
- `IntelligenceService`, `GenerationRequest`, `GenerationOutcome` compile
  with the shapes above; `GenerationRequest.zone` is 014 R1's `TrustZone`
  (Codable round-trip already tested under 014 R1's acceptance).
- A lint/code-review rule rejects any new `GenerationRequest`-conforming or
  -analogous type lacking a `zone` property (this is 014 R1's rule; cited
  here because this spec introduces the first real such type).
- Given any call through the protocol, when it completes, then the outcome's
  `zoneUsed`, `modelIdentifier`, `wasDegraded`, and `latency` are all
  populated — asserted in unit tests against a stub model, no real
  generation needed.

### R2. Table-driven `ModelRouter` with reasoning-level column
Routing is a literal data structure — one table, no scattered conditionals
(`REQ-INT-003`). The table is source doc §7.2's, extended with a
reasoning-level column per `technology/02` §5 (levels ✅ verified:
`.light`/`.moderate`/`.deep` via `ContextOptions(reasoningLevel:)`):

| Intent | Default zone | Reasoning | Degradation |
|---|---|---|---|
| Entry title | Z0 | — | none needed |
| Entry summary | Z0 | — | none needed |
| Mood + topics | Z0 | — | none needed |
| Salience score | Z0 | — | none needed |
| Entry reflection | Z0 | — | none needed |
| Weekly reflection | Z1 (PCC) | `.moderate` | Z0, reduced entry set, labeled |
| Monthly insight | Z1 (PCC) | `.deep` | Z0, shortened form, labeled |
| Ask (chat) | Z1 (PCC) | `.light` | Z0, narrower retrieval, labeled |
| Image understanding | Z0 | — | **none — no Z1 path exists** |

The reasoning column is a **starting hypothesis**, seeded from
`technology/02` §5's recommendation and validated by spec 013 Spike B and
spec 022's harness — Apple's explicit guidance is "data, not vibes," and
reasoning tokens count against the 32K PCC context (a `.deep` call over a
large retrieved set can exhaust context before producing output). Image
understanding is Z0-only with no degradation path: images are never sent to
PCC (`technology/01` §6). Z1 rows encode as
`.z1AppleContent(reasoningLevel:)` per R1's reconciliation.

`REQ-INT-004`: the table MUST be overridable by a user-facing setting
(source doc §10.2) that pins everything to Z0. The pin is a router-level
override, not per-surface logic — no surface can accidentally escape it.

**Acceptance:**
- The router is a value-typed table (array/dictionary of row structs), unit
  tested: every `GenerationIntent` case has exactly one row (exhaustiveness
  test breaks when a new intent is added without a row).
- Given the Z0-pin setting enabled, when any intent is routed — including
  weekly/monthly/ask — then the resolved zone is `.z0Device` and no PCC
  model is constructed; asserted per intent in unit tests.
- Given the image-understanding intent, when routed under any configuration,
  then no code path exists that yields a Z1 zone for it — asserted by test,
  and the row's degradation column is structurally empty (not "degrades to
  itself").
- Reasoning levels for the three Z1 rows match the table above until spec
  013 Spike B / spec 022 data says otherwise; changing them is a one-row
  table edit with a recorded rationale, not a code change elsewhere.

### R3. `QuotaGovernor` — reactive-first actor
A `QuotaGovernor` actor tracks PCC consumption locally and protects
scheduled surfaces (`REQ-INT-005`). Priority when budget is constrained:
**weekly reflection > monthly insight > chat** — a user must never lose
their Sunday reflection because they had a long conversation on Saturday
(`technology/02` §7).

The quota API surface is ✅ verified (`technology/02` §6):
`quotaUsage.status → .belowLimit(info)`, `info.isApproachingLimit`,
`quotaUsage.isLimitReached`, `quotaUsage.limitIncreaseSuggestion?.show()`.
Two verification items remain **open** and are designed around, not ignored:

- ⚠️ **V4 (open):** per-app vs per-user daily limit. `limitIncreaseSuggestion`
  pointing at iCloud+ implies **per-user across apps** — so the governor is
  designed **reactive-first**: it observes `quotaUsage`, tracks local
  consumption by intent, and treats budget *reservation* as advisory (another
  app may spend the budget; Memento can never know the true remainder). A
  per-app answer would be an upgrade (reservation becomes reliable), not a
  redesign.
- ⚠️ **V13 (open):** the full `quotaUsage.status` case list — only
  `.belowLimit(info)` is confirmed 🔴. The governor's switch over `status`
  MUST have a safe default arm so an unenumerated case degrades gracefully
  rather than crashing or silently misrouting; enumerate against the
  Xcode 27 SDK when available.

Behavior: chat has a soft local rate limit below the system limit so the
app degrades on its own terms with designed copy, never an opaque system
error (`REQ-INT-006`). When `isApproachingLimit` fires, chat degrades to Z0
*first*, preserving remaining budget for scheduled reflections. At the
point of exhaustion the app MAY mention factually that iCloud+ raises the
limit (surfacing `limitIncreaseSuggestion.show()`); it MUST NOT nag and
MUST NOT imply Memento requires iCloud+ (`REQ-INT-008`). All quota states
render through spec 014 R2's component — persistent inline UI, never an
alert (Apple's explicit guidance, `technology/02` §6). `REQ-INT-007`'s
⚠️ VERIFY is exactly V4 + V13, tracked in R10.

**Acceptance:**
- `QuotaGovernor` is an `actor`; unit tests drive it through
  available → approachingLimit → limitReached → reset using a stubbed quota
  surface (real-device states exercised via Xcode's "Simulate Apple
  Foundation Models Availability" debug option in UI tests, ✅ verified to
  exist).
- Given `isApproachingLimit == true`, when a chat request and a scheduled
  weekly reflection are both pending, then chat routes to Z0 and the weekly
  reflection keeps its Z1 route — asserted in a unit test of the priority
  order.
- Given the chat soft limit is reached (below system limit), when the next
  chat turn is sent, then it degrades per R4 with designed copy — the
  system's own limit error is never the user-visible surface.
- Given an unrecognized `quotaUsage.status` case (simulated), when the
  governor evaluates it, then it takes the conservative default arm (treat
  as constrained) rather than trapping — this is the V13 guard.
- No code assumes a knowable remaining budget (no "N requests left" UI or
  arithmetic) — reviewable assertion; this is the V4 posture.

### R4. Degradation contract — implements what 014 R2 promises
Z1→Z0 degradation is attempted automatically, completed successfully, and
disclosed (`REQ-INT-009`): persisted in spec 015's `Reflection.zone` /
`Turn.wasDegraded` fields and rendered via spec 014 R2's
zone-at-point-of-use component. The canonical degradation copy is **owned
by 014 R2's error-taxonomy table** ("Written on your iPhone. Shorter than
usual — your daily reflection allowance is used up until tomorrow.") — this
spec consumes it, never forks it per surface.

`REQ-INT-010` — non-negotiable (`technology/02` §8): degraded output uses a
**different prompt tuned for the smaller model**, never the PCC prompt with
a smaller model behind it (which produces confident, ungrounded, badly
structured output — the worst failure mode available). Mechanically: R8's
`PromptRegistry` holds a degraded variant for every Z1-capable intent, and
the degraded artifact's persisted `promptVersion` identifies that variant —
which is also how tests prove the right prompt ran. This is the procedural
half of the contract 014 R2 states declaratively; the disclosure UI is only
honest if this variant actually exists.

`REQ-INT-011` — the error taxonomy is design copy, not developer strings,
and MUST include **guardrail refusal as a designed state** (`technology/01`
§11): journaling content — grief, illness, conflict, self-critical language
— disproportionately trips safety guardrails. A refusal on the user's own
entry renders as the `hasNothingToSay`-style empty state (draft copy: "I
don't have an observation for this one."), never as an error, never
implying judgment of what they wrote. Refusal rate is logged against the
fixture corpus (metric owned by spec 022; if it exceeds a few percent, the
prompt framing is provoking it).

**Acceptance (Given/When/Then):**
- Given a Z1 request with `allowsDegradation == true` and quota exhausted,
  when it executes, then it automatically retries at `.z0Device`, succeeds,
  persists `zoneUsed == .z0Device` and `wasDegraded == true`, and the
  rendered artifact shows 014 R2's canonical degradation copy — never a
  silent, unlabeled Z0 result. (This is 014 R2's third Given/When/Then,
  restated here as the implementing spec's obligation.)
- Given a degraded weekly reflection, when its persisted `promptVersion` is
  inspected, then it names the degraded prompt variant, not the PCC prompt
  version — the `REQ-INT-010` proof.
- Given a guardrail refusal on an entry reflection, when the result renders,
  then the user sees the `hasNothingToSay`-style empty state with designed
  copy — no error alert, no retry spinner, no wording about "content
  policy."
- Given any degradation or refusal, when it occurs, then nothing the user
  wrote is lost — the entry and its transcript are untouched; only the
  generated artifact differs.

### R5. Guided generation contracts — `@Generable`, verbatim from §7.5
All structured output uses `@Generable` with `@Guide` descriptions; no
JSON-in-a-string parsing anywhere in the codebase (`REQ-INT-012`). The two
contracts are specified in source doc §7.5 and adopted **verbatim** — they
are interface contracts per §17, not sketches to redesign:

```swift
@Generable struct EntryReflection {
    @Guide(description: "Six words or fewer. No punctuation at the end. Reads naturally aloud.")
    let title: String
    @Guide(description: "One or two sentences describing what this entry was about, in plain prose. No lists, no markdown, no headers.")
    let summary: String
    @Guide(description: "Emotional valence from -1.0 (very difficult) to 1.0 (very good).")
    let valence: Double
    @Guide(description: "Up to three moods from the provided vocabulary.")
    let moods: [MoodLabel]          // enum, closed set
    @Guide(description: "Up to four topics from the provided vocabulary.")
    let topics: [TopicLabel]        // enum, closed set
    @Guide(description: "How much this entry stands out relative to an ordinary day, 0.0 to 1.0.")
    let salience: Double
}

@Generable struct PeriodReflection {
    @Guide(description: "Three to five sentences of continuous prose. Speakable: no markdown, no bullet points, no headings, no emoji. Written in second person.")
    let body: String
    @Guide(description: "One sentence. The single observation most worth keeping. Never advice. Never a question. Never comfort.")
    let observation: String
    @Guide(description: "The identifiers of entries this reflection is grounded in. Every claim must trace to one of these.")
    let groundedEntryIDs: [String]
    @Guide(description: "True if there was not enough material this period to say anything real.")
    let hasNothingToSay: Bool
}
```

`MoodLabel`/`TopicLabel` are closed, versioned enums — constrained decoding
means the model *cannot* emit an out-of-vocabulary value (`technology/01`
§4: "enums are the point"); the vocabulary version is stamped on the entry
so a future migration can re-tag. `hasNothingToSay` is a first-class
product feature, not an error path (`REQ-INT-013`): when true, the app
renders a deliberate empty state and generates no prose. Verify-first
items in the tool path: 🔴 tool registration form (instance vs metatype,
V10) and 🔴 `GenerationOptions.ToolCallingMode` (V11, matters for Ask's
"always search, never answer from world knowledge" rule) — confirm against
the Xcode 27 SDK before the ask intent's tool wiring is finalized.

**Acceptance:**
- Both structs compile field-for-field as above; `MoodLabel`/`TopicLabel`
  are `@Generable` enums with fixed case sets and a persisted vocabulary
  version.
- `grep -rn 'JSONDecoder\|JSONSerialization' ` over the intelligence module
  returns no generation-output parsing (persistence/manifest use is R8's
  business, tagged and allowlisted) — the `REQ-INT-012` "no JSON-in-a-string"
  rule as a checkable criterion.
- Given `hasNothingToSay == true`, when the reflection surface renders, then
  it shows the deliberate empty state and no prose body — UI test (surface
  itself lands in spec 019; the contract test here asserts no prose is
  generated/persisted).
- Given a `PeriodReflection`, when validated by spec 022's harness, then
  every `groundedEntryIDs` element resolves to a real entry ID — grounding
  is checkable, not aspirational.

### R6. Streaming split
Chat uses snapshot streaming for perceived latency
(`AsyncThrowingStream<AnswerChunk, Error>` in R1's protocol); reflections do
**not** stream — they arrive complete, because they are also audio artifacts
(source doc §8) and because a reflection assembling itself word by word
reads as a chatbot rather than a considered observation (`REQ-INT-014`).
This is a deliberate divergence in interaction model between the two
surfaces, not an implementation accident.

**Acceptance:**
- The protocol shape enforces it: `ask` returns a stream; `reflect`/
  `weeklyReflection`/`monthlyInsight` return complete values. No streaming
  variant of the reflection methods exists.
- Given a chat turn, when the model responds, then partial snapshots render
  incrementally; given a weekly reflection, when generation completes, then
  the UI receives exactly one complete artifact — asserted with a stub model
  in unit tests.

### R7. Provider escape hatch — seam proven, exit gated
The `IntelligenceService` implementation accepts its underlying
`LanguageModel` by injection (`REQ-INT-015`; the public `LanguageModel`
protocol is ✅ verified, `technology/01` §8). Swapping Apple's model for
Anthropic's or Google's conforming package MUST be a single
construction-site change, **exercised at least once in a test target** so
the seam is proven rather than assumed.

`REQ-INT-016`: the seam exists for survivability, not convenience. Shipping
a non-Apple provider changes the trust boundary from Z1 to **Z2** — which
spec 014 R1's `TrustZone` deliberately cannot even represent for
content-carrying calls — and MUST NOT occur without an explicit product
decision, a privacy label change, and updated user-facing copy. Non-goal
restated per §17: no Core AI custom weights in 2.0; that is the escape
hatch below the escape hatch.

**Acceptance (Given/When/Then):**
- Given a test-target fake conforming to `LanguageModel`, when the
  production `IntelligenceService` implementation is constructed with it,
  then all protocol methods run against the fake with no code change outside
  the construction site — one passing test, kept green permanently (this is
  the provider-swap test the Verification section requires).
- Given the shipping app target, when its dependencies are audited, then no
  non-Apple model provider package is linked — the escape hatch lives in
  test code only until the `REQ-INT-016` product decision is explicitly
  taken and recorded.

### R8. `PromptRegistry` — bundled prompts, versioning, DEC-003 OPEN
`PromptRegistry` is the deliberate replacement for the one genuine
capability regression of the rewrite (source doc §11.1, this spec's Why):

- `REQ-PRM-001` — prompts ship in-bundle as versioned resources, authored as
  Markdown in the repo, compiled into the binary at build time. Always
  present; always the fallback. The registry resolves
  `(intent, zone, degraded?) → (prompt text, promptVersion)` — the degraded
  variants R4 requires are registry entries, not string mutations.
  Shipping Ask is `ask@10` / `ask-degraded@10`: `[Turn:]` tags are stance
  **guidance** (prefer the intent), not a script the model must follow exactly.
- `REQ-PRM-002` — an optional remote prompt manifest MAY be fetched from a
  static host: signed JSON, CDN, no server logic; the request carries **no
  user data, no identifier, no query parameters**; fetch is weekly at most;
  failure is silent and falls through to bundled prompts; signature
  verification is mandatory before use.
- `REQ-PRM-003` — the remote fetch conflicts with a strict "no network
  calls" reading; Memento does not make that claim (`REQ-POS-001`, spec 014
  R3), so it is permissible — but it MUST be disclosed in the privacy
  explainer and MUST be disableable in Settings.
- **`DEC-003` — OPEN.** Ship remote prompts in 2.0, or defer to 2.1? The
  source doc's recommendation — build the mechanism, ship it disabled,
  enable in 2.1 once the privacy narrative is established — is this spec's
  working plan, but the decision itself is **pending, not decided**
  (source doc §15 lists it unresolved). Until it is taken: the code path
  exists behind a default-off flag, no fetch occurs in a shipping build,
  and the privacy-explainer copy change is not yet triggered.
- `REQ-PRM-004` — every generated artifact persists `promptVersion` and
  `modelIdentifier` (already fields on `GenerationOutcome`, R1); without
  this the quality study cannot attribute regressions and is worthless.
- `REQ-PRM-005` — the golden-set evaluation harness (fixture corpus, fixed
  question set, prompt version under test, output to disk) is owned by
  spec 022; this spec's obligation is that registry output is addressable
  by version so the harness can pin what it tests.

**Acceptance:**
- Given any intent/zone/degraded combination the router can produce, when
  the registry resolves it, then a bundled prompt with a version identifier
  is returned — exhaustiveness unit test; a missing combination is a test
  failure, not a runtime fallback to a "closest" prompt.
- Given a remote manifest with an invalid or missing signature (tampered
  fixture), when fetch completes, then the manifest is discarded and bundled
  prompts serve — silent fallthrough, no user-visible error, one log line
  at most (per spec 005's logging rules).
- Given a default configuration build, when the app runs, then **zero**
  remote prompt fetches occur (flag off per DEC-003's pending state) —
  asserted by network-audit test, and consistent with spec 014 R4's
  `NetworkCallSiteAudit` classification once that exists.
- Given any generated artifact, when persisted, then `promptVersion` and
  `modelIdentifier` are non-empty and spec 022's harness can read them —
  round-trip test against spec 015's models.

### R9. Context budgeting and session architecture
**Context budgeting is a contract, not a habit.** No hardcoded token
budgets anywhere in the module: read `contextSize` at runtime (✅ verified:
4096 iOS 26 / 8192 iOS 27 newer devices on-device; 32768 PCC), select
entries by `salience` ranking rather than dumping them (8K ≈ 25–30 moderate
entries *before* instructions, tools, and output), and instrument with
`response.usage` / `tokenCount(for:)` (✅ verified, iOS 26.4+) to detect
retrieved entries crowding out the reflection. Reasoning tokens count
against the PCC limit — R2's `.deep` monthly row spends context on thinking
before producing anything, and the budgeter must account for it.

**Session architecture — decision required (Task 11):** evaluate iOS 27
Dynamic Profiles (✅ verified, `technology/01` §7 — one session declaratively
swapping instructions/tools/model/reasoning between reflect and ask modes)
against the manual `transcript.dropFirstInstructions()` rebuild pattern
(also ✅ verified), and record in this spec which one `IntelligenceService`
uses and why. Until recorded, no code commits to either.

> **DECIDED (2026-08-11) — stateless per-request session assembly.** Each
> generation constructs a fresh `LanguageModelSession` from registry
> instructions plus the assembled prompt; the caller owns the transcript
> (`LocalChatStore`), retrieval is deterministic, and follow-up grounding is
> re-derived statelessly via `RetrievalPolicy.followupAnchor`.
>
> Rationale: Dynamic Profiles are an iOS-27 API and this target builds against
> the iOS 26 SDK, so they are not available to commit to; a
> transcript-preserving rebuild would duplicate state the chat store already
> owns and would have to be restored after relaunch. Stateless assembly
> survives relaunch with no session state at all and keeps the boundary
> testable without a live session. Revisit only if per-turn instruction
> re-tokenization shows up in spec 022's latency numbers — Dynamic Profiles
> remain an optimization, not a dependency. Recorded in
> `FoundationModelsIntelligenceService.swift`'s header.

**Acceptance:**
- `grep -rn '4096\|8192\|32768' ` over the intelligence module returns no
  matches outside comments/tests — the "no hardcoded budgets" rule as a
  checkable criterion.
  > **Amended (2026-08-11): that grep alone is not sufficient and was never a
  > real gate.** It passed on the pre-budgeting tree, because the module
  > hardcoded *derived* values (7 entries, 500 chars) rather than window sizes —
  > so it was green on a codebase that did no budgeting at all, and it would
  > also wave through `4 << 10`. `scripts/ci/check_no_hardcoded_context_budgets.sh`
  > (wired into `spec-gates.yml`) additionally requires: obfuscated window
  > literals to fail; every `prefix`/`suffix` payload cap to be budget-derived or
  > carry a `budget-exempt:` rationale; and a real `contextSize` read to exist,
  > without which the first two checks are trivially satisfied. Verified to FAIL
  > against `main` and pass on the implementing branch.
- Given a weekly reflection over a corpus larger than the runtime context
  allows, when entries are selected, then selection is by `salience` rank
  and the prompt fits the measured budget — unit test with the spec 013 R4
  fixture corpus.
- Given a completed generation, when `response.usage` shows retrieved
  context crowding out output (input near budget, output truncated), then
  the event is logged for spec 022's analysis — instrumentation exists, not
  just a TODO.
- The session-architecture decision is recorded in this spec with rationale
  before the ask surface's session code merges.

### R10. This spec's §16 verification-queue ownership
This spec owns source doc §16 items 4 and 14 (per the architecture spec's
§16→V-queue numbering map), both **partially resolved**:

- **Item 4 → V4, V13** — partially resolved: the quota API surface is
  ✅ verified (`quotaUsage.status`/`isApproachingLimit`/`isLimitReached`/
  `limitIncreaseSuggestion`, `technology/02` §6). **Outstanding:** V4
  (per-app vs per-user scope — plan for per-user, R3) and V13 (full `status`
  case list 🔴 — safe default arm required, R3). Both need the Xcode 27
  SDK/beta to close.
- **Item 14 → V28** — partially resolved: context sizes are ✅ verified
  (4096/8192/32768, R9). **Outstanding:** on-device latency on the minimum
  supported Apple Intelligence device — the p50 < 2s entry-reflection target
  (source doc §9.2) depends on it. **Gated on the Xcode 27 beta (not
  currently installed):** the measurement uses the Xcode 27 Foundation
  Models instrument, so Task 10 cannot run today; the acceptance criterion
  is the *plan* (instrument + oldest supported device, not a current phone),
  executed when the beta is available.

**Acceptance:** the V-queue entries for V4, V13, V28 are updated (closed or
still-open with findings) before this spec's status moves to done; no other
§16 items are owned here — 5 and 6 are spec 013 R5's, confirmed against
`technology/11-verification-queue.md`.

## Out of Scope

- The actual entry-reflection/weekly/monthly/ask *surfaces* that call this
  service — spec 019.
- TTS rendering of the resulting text — spec 018 (this spec only guarantees the
  text is speakable-shaped per `REQ-VOX-006`, enforced by that spec's
  `SpeakabilityLinter`).
- Monetization gating of which intents are free vs. paid — spec 021.

## Tasks
- [x] 1. Define `IntelligenceService` protocol + `GenerationRequest`/
      `GenerationOutcome` (`REQ-INT-001`, `REQ-INT-002`).
      > Landed 2026-08-11 with spec 014 R1's `TrustZone` (replacing the
      > two-case `IntelligenceZone`). `summarizeConversation` returns
      > `GenerationOutcome<String>`; `AskResult`/`ProfileEstimateResult` carry
      > zone, degradation, provenance, and latency inline because chat streams.
- [x] 2. Implement the table-driven router (`REQ-INT-003`, `REQ-INT-004`),
      including the reasoning-level column seeded from Spike B's recommendation.
- [x] 3. Implement `QuotaGovernor` reactive-first (`REQ-INT-005`–`008`) against
      the verified `quotaUsage` surface; ⚠️ V4 (per-app vs per-user) and V13
      (full `status` case list) remain open — plan for per-user.
- [ ] 4. Implement degradation contract with design-copy error taxonomy
      (`REQ-INT-009`–`011`), including guardrail refusal as a designed
      `hasNothingToSay`-style state; log refusal rate against the fixture
      corpus (metric owned by spec 022).
- [ ] 5. Implement `@Generable` contracts exactly per source doc §7.5
      (`REQ-INT-012`, `REQ-INT-013`).
- [ ] 6. Implement snapshot streaming for chat only, non-streaming for
      reflections (`REQ-INT-014`).
- [ ] 7. Implement the `LanguageModel` injection seam + a test proving provider
      swap works (`REQ-INT-015`, `REQ-INT-016`).
- [ ] 8. Implement `PromptRegistry`: bundled Markdown prompts (`REQ-PRM-001`),
      optional signed remote manifest built but shipped disabled per `DEC-003`
      (`REQ-PRM-002`, `REQ-PRM-003`).
- [ ] 9. Persist `promptVersion`/`modelIdentifier` on every generated artifact
      (`REQ-PRM-004`); confirm spec 022's eval harness can consume it
      (`REQ-PRM-005`).
- [ ] 10. ⚠️ VERIFY item 14, latency half only (V28): context sizes are now
      ✅ verified (4096/8192/32768); measure on-device latency with the Xcode 27
      Foundation Models instrument **on the minimum supported Apple Intelligence
      device, not a current phone** — the p50 < 2s entry-reflection target
      (source doc §9.2) depends on it.
- [x] 11. Decide the session architecture: Dynamic Profiles vs manual
      transcript-preserving rebuild; record the decision and rationale here.
- [ ] 12. Implement runtime context budgeting (read `contextSize`, rank by
      `salience`, instrument with `response.usage`); no hardcoded token numbers
      anywhere in the module.
      > **Partial (2026-08-11).** Landed: `ContextBudget` derives every payload
      > cap from the runtime window, no hardcoded token numbers remain, and
      > `check_no_hardcoded_context_budgets.sh` enforces it. **Not landed, and
      > blocked rather than skipped:** (a) `salience` ranking — `Entry` has no
      > `salience` field; it arrives with spec 015's SwiftData model and R5's
      > `@Generable EntryReflection`, so retrieval continues to rank by the
      > existing hybrid semantic + keyword + recency score; (b) `response.usage`
      > instrumentation — iOS 26.4+ API, not in the iOS 26.0 SDK this target
      > builds against. Both activate without call-site changes.
      >
      > Also note `contextSize` itself is **absent from the iOS 26 SDK**
      > (verified: zero occurrences in its `FoundationModels.swiftinterface`),
      > so the read is behind `#if compiler(>=6.3)` and the unread case is
      > modelled as `ContextWindow.unavailable` rather than defaulted to a
      > literal.

## Verification
- [ ] Single-importer lint (R1's exact grep) wired into CI and passing:
      exactly one Swift file imports `FoundationModels`, and it lives in the
      intelligence module.
- [ ] **Provider-swap test (`REQ-INT-015`) exists and passes** in a test
      target: the production `IntelligenceService` implementation constructed
      with a fake `LanguageModel`, all protocol methods exercised, no code
      change outside the construction site (R7).
- [ ] Router table tests pass: one row per intent (exhaustiveness), Z0-pin
      setting overrides every row including weekly/monthly/ask, image intent
      has no Z1 path (R2).
- [ ] `QuotaGovernor` unit tests cover available → approachingLimit →
      limitReached → reset, the weekly-over-chat priority order, and the
      unknown-`status`-case default arm; Z1 UI states exercised via Xcode's
      "Simulate Apple Foundation Models Availability" debug option (R3).
- [ ] Degradation tests pass: degraded artifact persists
      `zoneUsed == .z0Device` + `wasDegraded == true` (spec 015 fields),
      renders spec 014 R2's canonical copy, and its `promptVersion` names the
      degraded prompt variant, not the PCC prompt (R4, `REQ-INT-010` proof).
- [ ] Guardrail refusal renders the `hasNothingToSay`-style empty state with
      designed copy — no error alert — and refusal rate against the fixture
      corpus is logged for spec 022 (R4).
- [ ] `@Generable` contracts compile verbatim per §7.5; closed-enum
      vocabularies versioned; no generation-output JSON parsing in the module
      (R5's grep criterion).
- [ ] `PromptRegistry` tests pass: exhaustive `(intent, zone, degraded?)`
      resolution, tampered-manifest fixture falls through silently to bundled
      prompts, default build makes zero remote fetches (`DEC-003` still OPEN
      — mechanism built, shipped disabled, enable decision pending) (R8).
- [ ] `promptVersion`/`modelIdentifier` persisted on every artifact and
      readable by spec 022's harness (`REQ-PRM-004`/`005`).
- [ ] No-hardcoded-token-budget grep (R9) clean; salience-ranked selection
      tested against the spec 013 R4 fixture corpus; session-architecture
      decision (Dynamic Profiles vs manual rebuild) recorded in this spec.
- [ ] **Source doc §16 item 4** (→ V4, V13): quota API surface marked
      ✅ confirmed; V4 (per-app vs per-user) and V13 (full `status` case list)
      marked **outstanding** — closeable only against the Xcode 27 SDK;
      governor design holds under either V4 answer (R3, R10).
- [ ] **Source doc §16 item 14** (→ V28): context sizes marked ✅ confirmed
      (4096/8192/32768); on-device latency on minimum supported hardware
      marked **outstanding** — the Xcode 27 Foundation Models instrument is
      available (beta installed 2026-07-26); validation is now gated on a
      physical minimum-spec iOS 27 device; p50 < 2s target unvalidated until
      then (R10, Task 10).

## Regression Guards
`CONSTITUTION.md` §4 rule 5 ("exactly one Swift module imports `FoundationModels`")
is enforced by this spec and MUST be checkable by build configuration, not just
code review, before this spec can close. `CONSTITUTION.md` §4 rule 8
(`REQ-PRIV-001`) applies to every prompt this spec constructs — no journal content
in a Z1 prompt without the zone being correctly declared per spec 014.
