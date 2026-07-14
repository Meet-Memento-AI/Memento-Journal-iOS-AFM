# specs/ — App Store Readiness, Spec-Driven

This folder is the **single source of truth** for getting Memento from its current state
(branch `sync/upstream-main`) through TestFlight beta and into the App Store. It was
produced by a full three-track review (store configuration, iOS code quality,
backend/data layer) on 2026-07-13.

Each numbered file is an **executable spec**: a self-contained work-stream that one
implementation session (or 2–3 for the larger ones) can pick up, execute, verify, and
close without any other context. The numeric prefix is the recommended execution order.

```
specs/
├── README.md          ← you are here: workflow, tiers, template
├── CONSTITUTION.md    ← architecture baseline + non-regression contract
├── ROADMAP.md         ← status board, dependency graph, launch gates
└── 001…012-*.md       ← the twelve specs
```

---

## Priority tiers

Defined once here; specs reference them and never redefine them.

| Tier | Meaning | Gate |
|------|---------|------|
| **P0** | Blocks the TestFlight upload itself — archive fails, App Store Connect rejects the binary, or shipping it would be catastrophic (broken account deletion, irreproducible schema). | Gate 1 |
| **P1** | Blocks App Store review or a responsible public beta — guideline 5.1.1(v) compliance, unbounded LLM cost, PII in release logs, unauthenticated endpoints. | Gate 2 |
| **P2** | Production quality. Fix during the beta feedback window. | Gate 3 |
| **P3** | Post-launch. Parked in spec 012; harvest into new numbered specs when picked up. | — |

Launch gates are tracked in `ROADMAP.md`.

---

## Workflow protocol

How any session (human or agent) executes a spec:

1. **Pick**: open `ROADMAP.md`, choose the lowest-numbered spec whose `depends_on`
   entries are all `done`.
2. **Claim**: set the spec's front-matter `status: in-progress`.
3. **Re-verify the evidence**: the Current State table cites `file:line` references
   that were accurate on 2026-07-13. Line numbers rot. Confirm each row still holds
   before writing code; update stale references in the spec as you go. If a finding
   no longer reproduces, note it in the spec and skip its tasks.
4. **Execute**: work the Tasks checklist in order, checking boxes as you complete them.
5. **Verify**: run every item in the Verification section. A spec is not done until
   all of them pass.
6. **Guard**: re-check the spec's Regression Guards against `CONSTITUTION.md` —
   the strengths listed there must still hold after your changes.
7. **Close**: set `status: done (YYYY-MM-DD)` and tick the spec off in `ROADMAP.md`'s
   status board.

Rules of engagement:

- One spec per session by default. If a fix genuinely belongs to another spec
  (check its **Out of Scope** section), leave it — don't sprawl.
- Every schema change ships as a migration in `supabase/migrations/`. No ad-hoc SQL.
- Nothing in `CONSTITUTION.md`'s "verified strengths" list may regress silently.
- Commit per-spec (or per coherent task group), referencing the spec id in the
  commit message (e.g. `fix(store): add encryption compliance key [spec-002]`).

---

## Spec template

New specs (including anything harvested out of `012-post-launch-backlog.md`) follow
this exact shape:

```markdown
---
id: 0NN
title: Short Imperative Title
tier: P0 | P1 | P2 | P3
status: not-started | in-progress | done (YYYY-MM-DD)
effort: N sessions
depends_on: []            # spec ids that must be done first
findings: [kebab-slugs]   # one slug per finding this spec owns (greppable)
---

# 0NN — Title

## Why
2–4 sentences: user/business impact and which launch gate this blocks.

## Current State (evidence)
> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|

## Requirements
### R1. …
**Acceptance:** objectively checkable criteria.

## Out of Scope
What this spec deliberately does NOT do, and which spec owns it instead.

## Tasks
- [ ] 1. … (ordered; each maps to a requirement)

## Verification
- [ ] Commands / manual steps proving each acceptance criterion, runnable by a
      future session with no extra context.

## Regression Guards
CONSTITUTION.md strengths this work touches and must not break.
```

---

## Relationship to other documentation

| Location | Status |
|----------|--------|
| `docs/` | Engineering / how-it-works docs (RAG setup, CI policy, MEM-xx tickets) + hosted legal HTML. Unchanged, still authoritative for *how things work*. |
| `TESTFLIGHT_READINESS.md` (root) | **Superseded** by this folder (banner added). Kept as a historical record of pre-beta work completed in Oct 2025. |
| `.claude-instructions/` | Historical ad-hoc implementation plans. Read-only reference. |
| `.archive/APP_STORE_REJECTION_*.md` | Prior App Store rejection context — linked from spec 002. |
| `.sprints/` | Old sprint planning. Read-only reference. |

Status tracking lives **only** in spec front-matter + `ROADMAP.md`. No percentage
scores — they invite drift.
