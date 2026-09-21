---
id: 049
title: Epistemic Voice and Response Policy — Accuracy Before Resonance
tier: P1
status: draft (2026-09-21)
effort: sessions S6–S10 of the evidence-first program; voice stays
depends_on: [026, 037, 039, 046, 047]
findings:
  - first-person-perception-of-the-users-scene
  - narrative-join-across-unsupported-fragments
  - every-instruction-heard-as-distress
  - nearby-only-hedge-cites-then-denies
  - history-window-of-24-raw-messages
source_refs: [REQ-EPI-001, REQ-EPI-002, REQ-EPI-003, REQ-EPI-004, REQ-EPI-005, REQ-EPI-006, REQ-EPI-007, REQ-INT-001, REQ-PRM-004]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md]
---

# 049 — Epistemic Voice and Response Policy

**Traceability:** sits on the evidence gate in
[`046`](046-grounding-and-evidence-discipline.md) and the conversational
state in [`047`](047-conversational-state.md). Channel effort remains
[`039`](039-reply-channels-and-phatic-generation.md). Notebook voice remains
[`037`](037-conversational-recall-experience.md). Safety remains
[`026`](026-behavioral-safety-guardrails.md) and still runs first. This spec
mints the **`REQ-EPI-`** series inline.

**Does not implement:** a rewrite of specs 001–036, a second narration
stack, dynamic AFM profiles, an approximate-nearest-neighbor database, a
fact timeline with validity windows, or arming numeric gates from a single
run. The voice stays. Flattening imagery, short sentences, or quiet
language is a non-goal.

## Why

The 2026-09-20 study and the performance review found the same failure:
the model trades accuracy for resonance. It claims it saw the person's
scene, joins fragments the journal does not support, hears every
instruction as distress, and answers a task with another therapeutic
question. The nearby-only hedge cites an entry and then denies it. A
24-message raw history is what sat behind 976 `history_truncated` turns.

The product rule is unchanged: **code decides, the model renders.** Swift
picks the evidence rung and the response policy. The model writes the
sentence.

## Requirements

### R1. Perception ban (`REQ-EPI-001`)

The model must not claim it saw, heard, felt, noticed, smelled, or
remembered the person's scene. "I hear you" and "I'm here" stay legal.
`hall.firstPersonPerception` is report-only until two runs are warehoused.

### R2. Narrative-join ban (`REQ-EPI-002`)

The model must not join fragments the journal does not support ("you keep
tracing", "the pattern", "you're holding") when those words are not in the
user turn. `hall.narrativeJoin` is report-only.

### R3. Evidence ladder copy (`REQ-EPI-003`)

`EvidenceLadder` rungs are `exact`, `strong`, `ambiguous`, `none`, and
`conversationOnly`. Swift writes one line into the prompt. The model does
not pick the rung.

Fixed copy:

- exact — "You wrote X on [date]."
- strong — "Two entries are about this."
- ambiguous — "One entry may be what you mean."
- none — "I can't find an entry that supports that."

"I don't see anything from that stretch" is legal only on rung `none`.
Inventory with any hits uses `exact` or `strong`. A miss does not quote a
nearest entry. The `nearbyOnly` "closest entry is not the answer"
instruction is deleted (046 amendment).

### R4. Response policy (`REQ-EPI-004`)

`QuestionShape` and `ResponsePolicy` are chosen from the user text before
the model runs.

Shapes: `inventory`, `temporal`, `entity`, `advice`, `list`, `venting`,
`goodbye`, `correction`, `interpretationCut`, `specific`.

Policies: `answer`, `list`, `reflect`, `acknowledge`, `retract`, `abstain`.

- `reflect` (venting only): at most one concrete detail from the latest
  message, then one question.
- `list` and `answer` (advice, "give me a plan", "what are my options",
  "what would you do"): two or three options from what they said, no
  required question, and never "you should" (026 stays).
- `acknowledge` (goodbye): no question.
- `abstain`: may say the fragments do not have to mean anything together.
- `retract`: acknowledge, name the inference, continue from the user's
  words. The retracted claim is stored and the next turn must not repeat
  it.

One suffix per policy. `rule.noOpen` does not fire on `list`, `answer`,
`acknowledge`, `retract`, or empty statistic bodies (039 amendment).

"Last Tuesday" and "before the pottery class" filter `createdAt`. Cosine
must not win because the query contains the anchor word.

### R5. One-detail reflection (`REQ-EPI-005`)

A reflect turn names at most one concrete detail from the latest user
message, then asks one question. It does not answer a task with another
therapeutic question.

### R6. History window (`REQ-EPI-006`)

Notebook and companion prompts receive a short rolling summary, the last
four turns, and the current message. Notebook prompts also receive the
evidence passages. They do not receive 24 raw messages. A cap cut ends on
a sentence boundary. Narration stays on `askStream`. Spoken notebook stays
on `LightAskAnswer`.

### R7. Voice non-goal (`REQ-EPI-007`)

Imagery, short sentences, and quiet language stay. Epistemic accuracy is
not purchased by flattening the voice.

## Out of Scope

- Rewriting 001–036.
- A second narration intelligence stack.
- Dynamic AFM profiles.
- An approximate-nearest-neighbor database.
- A fact timeline with validity windows.
- Arming numeric gates from a single run, including `hall.fabricatedQuote`.

## Tasks

- [x] 1. Evidence ladder copy; delete the nearbyOnly hedge; bump
      `ask-core@17` to `@18`. (R3)
- [x] 2. `QuestionShape` and `ResponsePolicy`; date filters for "last
      Tuesday" and "before &lt;anchor&gt;". (R4)
- [x] 3. Perception and narrative-join lines in the prompt; one-detail
      reflection. (R1, R2, R5)
- [x] 4. `HistoryWindow`: summary plus last four turns plus passages. (R6)
- [x] 5. Register in `specs/README.md` and `ROADMAP.md` phase 9.

## Verification

- [ ] Advice opener resolves to `list`; a goodbye resolves to `acknowledge`.
- [ ] "Before the pottery class" does not rank the pottery entry first when
      earlier entries exist.
- [ ] `AskPromptSizeTests` stays inside the existing core budget.
- [ ] `AskLatencyFloorTests` stays green.
- [ ] Perception, narrative-join, and fabricated-quote scorers stay
      report-only until two warehoused runs.

## Regression Guards

- **Spec 037 voice** — imagery and quiet language are not deleted to buy
  accuracy.
- **Spec 026** — "you should" stays forbidden; safety still runs first.
- **Spec 029** — narration stays on `askStream`; first sentence still goes
  to TTS with the existing lookahead.
- **Single importer** — `check_single_intelligence_importer.sh` still
  reports 1.
