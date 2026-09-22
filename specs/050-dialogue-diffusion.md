---
id: 050
title: Dialogue Diffusion — Repair the Spans That Miss the Policy
tier: P2
status: in-progress (2026-09-22 — closed-form reverse step landed; typed infill not wired)
effort: 1 session for the scheduler; the infill call waits on a measured residual
depends_on: [039, 048, 049]
findings:
  - policy-and-channel-both-instruct-the-question
  - structural-miss-is-a-span-not-a-reply
  - second-generation-cannot-sit-in-front-of-tts
source_refs: [REQ-EPI-004, REQ-EPI-005, REQ-EPI-007, REQ-INT-017, REQ-PRM-004]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md]
---

# 050 — Dialogue Diffusion

**Traceability:** the expectation is already
[`049`](049-epistemic-voice-and-response-policy.md)'s `ResponsePolicy`,
chosen before the model runs. Channel effort stays
[`039`](039-reply-channels-and-phatic-generation.md). Spoken first-sentence
latency stays [`029`](029-performance-and-speech-excellence.md). Serial
generation cost stays [`048`](048-harness-depth-ii.md) finding 6. This spec
does not mint a new `REQ-` series; it spends `REQ-EPI-004` on the residual
the policy suffix does not reliably win.

**Does not implement:** a diffusion language model, a second decoder family,
best-of-n sampling, a rewrite of the notebook voice, or a denoise step on
the spoken path before the first sentence reaches TTS.

## Why

The current model is Apple's on-device Foundation Model, about 3B, one
guided generation per turn. The harness around it is a deterministic
orchestrator: `TurnClassifier` → `ReplyChannel` → retrieval → `QuestionShape`
→ `ResponsePolicy` → one `AskAnswer` or `LightAskAnswer` stream. The product
rule from 037/039/049 still holds: **code decides, the model renders.**

That split is the right place for the remaining dialogue bugs. They are not
"the agent does not know what the user wanted." Swift already knows:

| User said | Shape | Policy | What the reply owes |
|---|---|---|---|
| "goodnight" | `goodbye` | `acknowledge` | a close, no question |
| "what should I do about the work situation" | `advice` | `list` | two or three options, no "you should", no required question |
| "Saw a rat in the lab fridge" | `venting` | `reflect` | one concrete detail, then one question |
| "you got that wrong" | `correction` | `retract` | name the inference, do not repeat it |
| a journal miss | `specific` + ambient | `abstain` | the fragments do not have to mean anything together |

The miss is local. A goodbye still grows a question. A list still says "you
should." A reflection claims "I saw" or "you're holding." The rest of the
sentence is fine. The Hamming distance between the draft and the reply the
policy asked for is a span, not a document.

Two instructions currently argue about that span. `ask-core@18` says Open
is "required except goodbye" and "exactly one question mark, in the final
sentence." The notebook channel suffix says "then one question" on every
stance, including the one the per-turn policy has just set to
`Acknowledge: close warmly. No question.` On a model this size the standing
instruction often wins. Diffusion does not replace that fix. It cleans the
spans the contradiction still produces.

## How to use diffusion

Use it as **discrete diffusion over the draft**, conditioned on the policy
Swift already chose. Do not use it as the generator.

1. **Leave the decision alone.** Diffusing `QuestionShape` or
   `ResponsePolicy` would make the expectation stochastic. That is the bug
   049 removed when the model was picking the evidence rung.
2. **Do not swap in a diffusion language model.** The runtime is one serial
   Foundation Models session at about 2.06s p50 (`048` finding 6). A masked
   diffusion LM (LLaDA-style iterative decode) cannot run here, and the
   quality ceiling is still retrieval plus the policy, not the decoder
   family. Guided `AskAnswer` stays the generator.
3. **Do not sample a cloud of replies.** Best-of-n is diffusion's cousin and
   it is the same serial cost multiplied. 048 already rejected designs that
   need that many generations.
4. **Forward step: mark noise, do not add it.** The noise is the spans that
   violate the policy. Question budget, "you should", a perception verb
   (`hall.firstPersonPerception`), a narrative join (`hall.narrativeJoin`),
   a banned opener. Nothing else is noise. Imagery, short sentences, and
   quiet language stay (`REQ-EPI-007`). A scorer that cannot name a span
   does not get to edit.
5. **Reverse step, structural, in code.** A question on `acknowledge`, or a
   second question on any policy, has one legal edit: delete the surplus
   question sentence, keeping the last one when the budget is 1. If the
   whole reply is a question and the budget is 0, flatten the mark so the
   close is not erased, and name the sentence for a later rewrite. This
   step is `DialogueDiffusion.denoise`. It does not call the model. A model
   infill of "delete the question mark" is slower and can put the question
   back.
6. **Reverse step, semantic, one infill, typed only.** "you should", "I
   saw", "you're holding", and "You wrote…" need a rewrite of that sentence,
   not a deletion. `DialogueDiffusion.infillInstruction` is the one line
   that call would see. Cap it near 40 tokens. Rescore. If the infill adds
   a violation, is longer, or is empty, keep the closed-form body. Run it
   only when an infill was named. The common turn is already clean and
   must not pay a second generation (`039`'s effort curve).
7. **Do not put either reverse step in front of TTS.** Spec 029 sends the
   first sentence as it streams. A denoise that waits for the full body
   misses that, and a denoise that rewrites a sentence already spoken makes
   the transcript and the audio disagree. Spoken turns keep the draft.
   Typed chat can denoise before the bubble is committed. The stored
   assistant turn is the denoised body only when the user is reading, so
   the next turn does not continue from the agent's own stray question.

What this is not good at: a wrong policy. If `QuestionShape` calls a task
venting, diffusion will faithfully repair a reflection the user did not
ask for. Fix the classifier. Diffusion preserves the decision; it does not
re-decide.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Policy is chosen before generation and appended as one suffix | `ResponsePolicy.swift` `policy(shape:evidence:)`; `PromptRegistry.policySuffix`; `FoundationModelsIntelligenceService.buildAskPrompt` appends it on both the short and the full assembler | — (the condition) |
| 2 | The standing voice still requires one question, including on channels whose per-turn policy may forbid it | `PromptRegistry.swift` `askCore` Open bullet ("required except goodbye"); `notebookSuffix` "then one question"; phatic/continuer reuse `notebookSuffix` via `channelSuffix` | High |
| 3 | Epistemic checks log and do not rewrite | `EpistemicGuard.swift` "It does not rewrite the voice."; `makeResult` logs `finding.code` and returns `cleanedBody` | High |
| 4 | Question-count and perception scorers already exist, in the test target | `ChatEvalScoring.ruleBreaks` (`rule.noOpen`, `rule.multipleQuestions`); `firstPersonPerception`; `narrativeJoin` | — (the noise detector) |
| 5 | A second full generation is serial and about 2s | `048` finding 6, `ModelRuntimeGate` | — (the constraint) |

## Requirements

### R1. Closed-form reverse for the question budget

`DialogueDiffusion.denoise(body:policy:userTurn:)` returns the input string
unchanged when the question count is inside the budget. `acknowledge`
budget is 0. Every other policy's budget is 1. Surplus question sentences
are dropped earliest-first, so the question the prompt asked to put last
is the one that remains. A reply that is only questions under a zero budget
is flattened (last `?` becomes `.`) rather than erased, and that sentence
is returned as infill `dialogue.questionOnAcknowledge`. A second call on
the result is a no-op.

**Acceptance:** `DialogueDiffusionTests` covers a clean goodbye, a goodbye
with a trailing question, a question-only goodbye, a reflect with two
questions, and a list that keeps its single question.

### R2. Semantic spans are named, not rewritten

Perception verbs, narrative-join phrases absent from the user turn,
"you should" absent from the user turn, a banned opener, and a missing
Open on `reflect` / `abstain` are returned in `infill` with a code and the
sentence. The body is unchanged. "I hear you" is not perception. A phrase
the user already used is not noise. `infillInstruction` names the one
sentence to rewrite and the policy constraint. No Foundation Models import.

**Acceptance:** the perception, narrative-join, banned-opener, "you should",
and missing-Open tests. A user turn that already contains the phrase does
not produce that code.

### R3. Typed infill stays unwired until the residual is measured

The model call described in step 6 of "How to use diffusion" is not part of
`makeResult` in this session. Wiring it before a warehoused run would spend
a second generation on an unmeasured rate, and wiring it into the spoken
stream would break 029. When it lands: typed channel only, only if `infill`
is non-empty after R1, one call, rescore, keep the pre-infill body on any
new violation.

**Acceptance:** `DialogueDiffusion.swift` does not import `FoundationModels`.
`makeResult` still returns the cleaned draft.

## Out of Scope

- Replacing Foundation Models with a diffusion LM.
- Best-of-n or any design that generates more than one extra call per turn.
- Rewriting imagery or shortening sentences to buy compliance (`049` R7).
- Changing `ask-core@18` or the channel suffixes. The contradiction in
  evidence row 2 is real and should be fixed in the prompt spec that owns
  those strings; this spec only stops spending a model call to paper over it.
- Running the reverse step before the first spoken sentence.

## Tasks

- [x] 1. `DialogueDiffusion` question-budget reverse step. (R1)
- [x] 2. Semantic infill records, no model call. (R2)
- [ ] 3. Typed-only infill behind a measured residual. (R3)
- [x] 4. Register in `specs/README.md` and `ROADMAP.md` phase 9.

## Verification

- [ ] `xcodebuild test -only-testing:MeetMementoTests/DialogueDiffusionTests`
      on a Mac with the iOS SDK. This session ran on Linux and did not
      execute it.
- [ ] A clean body is pointer-equal in content to the input, including
      newlines.
- [ ] `DialogueDiffusion.swift` has no `FoundationModels` import.

## Regression Guards

- **Spec 029** — spoken streaming is untouched. `makeResult` does not call
  `denoise`.
- **Spec 039** — a clean phatic turn does not gain a generation.
- **Spec 049 R7** — the reverse step deletes surplus question sentences and
  does not otherwise restyle the body.
- **Single importer** — no new `FoundationModels` import.
