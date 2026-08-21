---
id: 026
title: Behavioral Safety Guardrails
tier: P0
status: in-progress (2026-08-19) — Safety stack shipping; PersonaGate re-run on ask@10 fixtures in CI
effort: 2 sessions
depends_on: [017, 019, 022]
findings: [deterministic-pre-gate, static-crisis-card, hard-refuse-taxonomy, output-scanner, persona-gate-expansion]
source_refs: [REQ-SUR-004, REQ-INT-011, REQ-SUR-002]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md]
---

# 026 — Behavioral Safety Guardrails

**Traceability:** closes the safety hole left open by `specs/019-surfaces.md` R7
(`REQ-SUR-004` static crisis card; dedicated safety spec was missing) and
`specs/022-evaluation-and-quality-study.md` PersonaGate (crisis-routing 100%,
no-advice ≥ 98%, no-diagnosis 100%). Extends adversarial coverage beyond advice /
diagnosis / crisis into violence, terrorism/mass-violence assistance, CSAM,
jailbreaks, and regulated advice.

## Why

Ask orchestration (TurnClassifier → Retrieval → PromptRegistry → AFM) had only
soft prompt rules and Apple's opaque `guardrailViolation` backstop. Crisis copy
in `ask@5` instructed the **model to generate** counseling + 988 — contradicting
019 R7's **static card, zero generated counseling**. Violence, terrorism,
CSAM, and jailbreaks had no pre-model gate. This spec defines the on-device,
deterministic Safety layer that runs **before retrieval** and validates output
**after generation**.

## Technology References

- `specs/reference/technology/01-foundation-models.md` — AFM `guardrailViolation`
  remains a last-layer backstop, never the product safety system.
- `specs/reference/technology/04-evaluations.md` — PersonaGate thresholds and
  adversarial fixture layout.

## Requirements

### R1. Harm taxonomy (`SafetyCategory`)

```
csam
terrorismMassViolence
violenceOthers
selfHarmCrisis
hateHarassment
jailbreak
regulatedAdvice
clear
```

### R2. Actions (`SafetyAction`)

| Action | Behavior |
|---|---|
| `showCrisisCard` | No `session.respond`. Render static crisis resource card. |
| `hardRefuse` | No `session.respond`. Render authored refuse template. No retrieval. |
| `continueConstrained` | Run pipeline; force no-advice / no-diagnosis stance overlay. |
| `continue` | Existing TurnClassifier path. |

### R3. Precedence (highest wins)

CSAM → terrorismMassViolence → violenceOthers → selfHarmCrisis → hateHarassment → jailbreak → regulatedAdvice → clear.

### R4. Pre-model gate

`SafetyClassifier` (lexicon/regex, precision-biased) + `SafetyRouter` run inside
`FoundationModelsIntelligenceService.prepareAsk` **before** retrieval. Same
classifier gates `summarizeConversation` and `estimateProfile` inputs (refuse
suicide-note / violent-plan production).

### R5. Static crisis card (`REQ-SUR-004`)

Bundled, locale-keyed resources (no network). Ask mounts `CrisisResourceCard`.
Generated counseling is forbidden on this path.

### R6. Prompt L0 alignment

`ask@6` / `ask-degraded@6` remove generative crisis instructions; add hard bans
for violence, terrorism, weapons, CSAM, self-harm methods, jailbreaks, goodbye
notes. Degraded prompt carries the **same** L0 bans. Summarize + profileEstimate
carry parallel L0 lines.

### R7. Output scanner

`OutputSafetyScanner` inspects final (and stream-final) assistant text. Hits
replace with crisis card or hard refuse; unsafe body is not persisted.

### R8. Telemetry

Local counters by category/action enum only — **never** message plaintext.

### R9. Evaluation

PersonaGate (and SafetyClassifier unit tests) over expanded
`Fixtures/gold/adversarial.json`. Crisis-routing **100%**; no-diagnosis **100%**;
no-advice ≥ **98%**; new categories must map to expected `SafetyAction`.

## Non-goals

- Third-party cloud moderation APIs (breaks Z0 / privacy).
- Clinical intervention or chat-based therapy.
- Perfect semantic coverage of all coded language (iterate via gold fixtures;
  ambiguous crisis cues fail closed toward the card).
- PCC/Z1-specific prompts (same L0 bans when Z1 ships).

## Acceptance

1. Every `crisis` adversarial prompt → static card; zero `session.respond`.
2. Violence / terrorism-actionable / CSAM / jailbreak → hard refuse; no retrieval.
3. `ask-degraded` contains the same hard safety bans as full ask.
4. Output scanner blocks canned unsafe completions in unit tests.
5. No safety path logs or persists user plaintext for telemetry.
