---
id: 047
title: Conversational State — Reachable Follow-ups and Corrections That Land
tier: P2
status: draft (2026-09-20)
effort: 3–4 sessions
depends_on: [037, 039, 046]
findings:
  - followup-gate-never-enabled-in-typed-chat
  - thread-channel-and-reuse-previous-are-unreachable
  - correction-absorbed-by-share-default
  - no-retraction-behaviour
source_refs: [REQ-CST-001, REQ-CST-002, REQ-CST-003, REQ-INT-017, REQ-SUR-002]
tech_refs: [technology/04-evaluations.md]
---

# 047 — Conversational State

**Traceability:** repairs the turn-routing layer that spec
[`037`](037-conversational-recall-experience.md) shapes and spec
[`039`](039-reply-channels-and-phatic-generation.md) channels. The classifier, the
retrieval policy and the channel table are all unchanged in design — this spec
makes two of their existing branches reachable and adds one missing turn type. It
depends on [`046`](046-grounding-and-evidence-discipline.md) because evidence state
must already gate the channel before `thread` starts receiving real traffic. The
instrument that makes the migration safe is [`048`](048-harness-depth-ii.md) R2.
Mints the **`REQ-CST-`** series inline.

**Does not implement:** safety routing, which runs first and is unchanged
([`026`](026-behavioral-safety-guardrails.md)); narration
([`028`](028-conversational-narration.md)); the spoken follow-up recipe
(`ReplyChannel.applyingSpokenFollowUpRecipe`), which already works and is the one
path where the follow-up gate is live today.

## Why

The 2026-09-20 study measured `TurnType.followup` on **5 of 3,492** assistant turns
(0.14%), against 3,292 turns that had two or more prior messages. The `thread`
channel received 5 turns across 200 conversations. Everything gated on that
classification — `RetrievalMode.reusePrevious`, `followupAnchor`'s four-turn
walkback and its memo cache, the `followupThread` stance and its "continue the same
thread, do not restart with a new heading" behaviour — is therefore unreachable in
typed chat.

The classifier is not at fault. Its `lastAssistantAskedQuestion` branch is written
for exactly this shape and is covered by tests. It is simply never switched on
outside voice narration, while the persona recipe ends nearly every reply with a
question — so typed users answer a question on most turns, and each answer is
classified `share`.

The same study found corrections absorbed by the same `share` default: all 20
correction openers classified `share` → `companion`, and of 42 user turns that read
as a correction, 31% drew a reply that acknowledged being wrong. A journal assistant
that cannot take a correction is a trust problem distinct from fabrication, and
nothing measures it.

Tier P2: production quality, fixed in the beta window. It does not block review.

## Technology References

- `technology/04-evaluations.md` — measure first, threshold after. R1 changes routing
  for every typed user, so it lands report-only behind `048` R2's confusion matrix and
  is adopted only after two warehoused runs show the effect.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Verified 2026-09-20.
> Rates come from 3,492 assistant turns in
> `.eval-runs/convo-sim/full-2026-09-20.jsonl`. The simulated *person* is a 3B model
> playing a persona brief; rows 1–3 are structural and independent of that, row 5 is
> a keyword-proxy rate and is directional only.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **The follow-up gate is never enabled in typed chat.** Both production call sites disable it: `answeringLastQuestion = origin == .narration && …` and `answeringLastQuestion = spoken && …`. No call site anywhere passes `spoken: true`; `.narration` is set only by `NarrationCoordinator`. | `ChatViewModel.swift:432-438`, `FoundationModelsIntelligenceService.swift:914-919`, `NarrationCoordinator.swift:532` | High |
| 2 | **`.followup` fires on 0.14% of turns.** 5 of 3,492, against 3,292 turns with ≥2 prior messages. Without the gate, only three narrow paths remain: an 18-phrase closed lexicon, three literal tokens (`why` / `why not` / `really`), and a ≤8-word question whose content words are all deictic. | `TurnClassifier.swift:76-84` (lexicons), `:273-320` (rule 4); `.eval-runs/convo-sim/full-2026-09-20.jsonl` | High |
| 3 | **A whole retrieval path is consequently dead.** `RetrievalMode.reusePrevious` exists only to be returned by `followupMode`; `.thread` is one of only two channels with `allowsRetrieval`; `followupThread` is one of only two stances that may legitimately cite. The memo cache built to make repeated walkbacks cheap is unexercised. | `RetrievalPolicy.swift:125-167`, `:106-115`, `:66-69`, `:177-193`; `ReplyChannel.swift:34`, `:134-139` | High |
| 4 | **The eval harness reproduces the defect independently.** `ConversationSimulation` classifies without the parameter, so a fix to the production call sites alone will not appear in a re-run. | `withMementoTests/Eval/ConversationSimulation.swift:191` | Medium |
| 5 | **Corrections are routed as sharing, and rarely land.** All 20 correction openers classified `share` → `companion`. Of 42 user turns matching a correction pattern, 13 (31%) drew a reply acknowledging the error. There is no correction turn type, no retraction, and no scorer for either. | `TurnClassifier.swift:365` (`share` default); `.eval-runs/convo-sim/full-2026-09-20.jsonl` | Medium |
| 6 | **The gate itself is correct and already covered.** `TurnClassifierTests` exercises `lastAssistantAskedQuestion: true` directly, including the journal-ask, off-domain and social forks that must *not* become follow-ups. | `withMementoTests/TurnClassifierTests.swift:177-208` | — (reuse, do not duplicate) |

## Requirements

**Traceability:** R1 → `REQ-CST-001`; R2 → `REQ-CST-002`; R3 → `REQ-CST-003`.
All Z0 (on-device); nothing here changes what leaves the device.

### R1. The follow-up gate reaches typed chat (`REQ-CST-001`)

Ungate `answeringLastQuestion` so it is computed from conversation state rather than
from input modality, at `ChatViewModel.swift:432` and
`FoundationModelsIntelligenceService.swift:914`, and at the harness call site
(`048` R5). A person answering the question the assistant just asked is answering it
whether they typed it or spoke it.

**This is an enablement change, not a classifier rewrite.** The branch, its
exclusions (a turn carrying its own journal ask, an off-domain question, a reflective
question) and its tests already exist. Extend `TurnClassifierTests`' existing fork
cases; do not re-prove the fork works.

Treat it as a measured migration, because it moves traffic for every typed user:
land behind `048` R2's route-coverage matrix, warehouse two runs, compare, then
adopt. Report the resulting `followup` rate, `thread` share and
`reusePrevious` rate per run.

**Acceptance:**
- Given a typed conversation whose previous assistant turn ended in a question, when
  the person answers it without deixis and without a fresh journal ask, then the turn
  classifies `.followup`.
- Given the same shape where the answer is itself a journal ask, an off-domain
  question or a reflective question, then it does **not** classify `.followup` —
  the existing exclusions still hold.
- Given a replay of the archived corpus with the gate enabled, then the `followup`
  rate, `thread` channel share and `followupAnchor` execution rate are each reported
  and non-zero.
- Given `RetrievalPolicyTests`, then its `mode` matrix and `followupAnchor` walkback
  assertions still pass unchanged.

### R2. A correction turn type and stance (`REQ-CST-002`)

A person contradicting a claim the assistant made is not sharing a feeling. Add the
turn type, a stance that acknowledges the error and retracts the claim, and route it
away from `companion`.

Ordering is the whole design. The classifier is deliberately precision-biased — its
header records that ambiguous messages fall through to `share` / `journalQuery`.
Correction must therefore be tested **after** the high-precision social,
acknowledgement and meta rules, and **before** the `share` default that currently
absorbs it, without widening into ordinary disagreement about the person's own life
("I don't think that's why I was tired" is reflection, not a correction of the
assistant).

The stance must retract rather than merely apologise: the retracted claim must not
be restated as fact later in the same reply, which is the failure mode worth
measuring.

**Acceptance:**
- Given a scripted correction of a claim the assistant made in the previous turn,
  then the turn classifies as the correction type and routes away from `companion`.
- Given that stance, then the reply acknowledges the error and does not restate the
  retracted claim anywhere in the same body.
- Given a message that disagrees with an interpretation of the person's own life
  rather than with an assistant claim, then it does **not** classify as a correction.
- Given `PromptStanceSyncTests`, then its "every stance the channel can emit appears
  in that channel's suffix" assertion still holds with the new stance.

### R3. Correction and retraction scorers (`REQ-CST-003`)

Two report-only scorers in `ChatEvalScoring`, consumed by `048`: did the reply
acknowledge the correction, and did it restate the retracted claim. Both ship with a
positive fixture, per `046` R1 — a scorer without one is not a scorer.

**Acceptance:** given a correction scenario, then both scorers emit a decision rather
than silence; given `ChatEvalScoring.gating`, then neither code gates until two runs
are warehoused.

## Out of Scope

- Safety routing (`026`) — runs before any of this and is unchanged.
- Narration (`028`) and the spoken follow-up recipe, which already work.
- Evidence state and channel gating — [`046`](046-grounding-and-evidence-discipline.md) R3.
- The route-coverage matrix and the harness call-site fix —
  [`048`](048-harness-depth-ii.md) R2 / R5.
- Widening the follow-up phrase lexicon. The gate, not the lexicon, is the constraint.

## Tasks

- [ ] 1. Compute `answeringLastQuestion` from conversation state at both production
      call sites; extend `TurnClassifierTests`' existing fork cases. (R1)
- [ ] 2. Land R1 report-only behind `048` R2; warehouse two runs; record the routing
      delta in the PR body. (R1)
- [ ] 3. Add the correction turn type with its ordering, plus the retracting stance
      and its channel suffix entry. (R2)
- [ ] 4. Add the acknowledgement and retraction scorers with positive fixtures. (R3)
- [ ] 5. Register in `specs/README.md` and `ROADMAP.md`. (—)

## Verification

- [ ] `xcodebuild test -only-testing:withMementoTests/TurnClassifierTests
      -only-testing:withMementoTests/RetrievalPolicyTests
      -only-testing:withMementoTests/ConversationFlowTests` green.
- [ ] `xcodebuild test -only-testing:withMementoTests/PromptStanceSyncTests` green
      after the new stance lands.
- [ ] `DiagTurnRouting` report shows the follow-up rows resolving to `thread`, and
      the correction rows resolving away from `companion`.
- [ ] Two warehoused runs (`043`) show the `followup` rate, `thread` share and
      `reusePrevious` rate before and after R1.
- [ ] A fresh correction scenario set reports acknowledgement and non-restatement
      rates; no threshold is armed on the first run.

## Regression Guards

- **Spec 037 / `TurnClassifier`'s precision bias** — the no-retrieval turn types fire
  only on high-precision patterns; ambiguity falls through to `share` / `journalQuery`.
  R2 must not turn that default into a correction catch-all.
- **`RetrievalPolicyTests`' mode matrix** — `followupMode` still returns `.none` when
  the anchor is a share, so a social continuer never loads the notebook.
- **Spec 039 channel budgets** — `thread` keeps its existing token cap and
  temperature; this spec changes how often it is reached, not what it does.
- **Spec 026** — safety routing runs before classification and is untouched.
- **`046` R3** — with evidence state gating the channel, `thread` can only be reached
  when there is something to reuse; R1 must not create a path into `thread` on an
  empty archive.
- **CONSTITUTION §4 rule 6** — new behaviour ships with tests, in the same PR.
