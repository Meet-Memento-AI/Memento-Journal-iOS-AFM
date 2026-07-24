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
├── 001…012-*.md       ← the original twelve specs (pre-2.0 app; 003/004/007/008/010
│                        obsolete, 002 paused — see ROADMAP.md's Status board)
├── 013…023-*.md       ← Memento 2.0 rewrite specs (see below)
└── reference/
    ├── memento-2.0-architecture-spec.md      ← 2.0 source-of-truth, cited by REQ-/DEC- ID
    ├── frontend-preservation-contract.md     ← front-end non-regression contract, cited by PRES- ID
    └── technology/                           ← Apple-framework API reference library
        └── 00…11-*.md                        ← cited by tech_refs in specs 013–023
```

Specs 013+ implement the Memento 2.0 rewrite described in
`specs/reference/memento-2.0-architecture-spec.md` (deleting the Supabase/pgvector/
Gemini backend in favor of on-device SwiftData + Core Spotlight + Apple Foundation
Models). They follow the exact same template and workflow as 001–012 below — the
only additions are that their front-matter and body cite the `REQ-XXX-nnn`/`DEC-nnn`
IDs they derive from, so a decision made in the source document is traceable to the
numbered spec that resolves it, and that they cite the specific
`specs/reference/technology/*.md` file(s) an implementer should read for
Apple-framework API behavior (`tech_refs:` front-matter plus a "Technology
References" body section — a WWDC26-sourced API library using the same
✅ VERIFIED / 🟡 LIKELY / 🔴 UNVERIFIED confidence markers as the source document's
`⚠️ VERIFY` items, see `specs/reference/technology/00-INDEX.md`). `ROADMAP.md`'s
"2.0 Rewrite — Phase Plan" section is the status board for these.

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
   no longer reproduces, note it in the spec and skip its tasks. For specs 013+,
   also check the confidence markers (✅ VERIFIED / 🟡 LIKELY / 🔴 UNVERIFIED) in
   each file listed under `tech_refs:` — anything 🔴 that blocks your task should
   already be filed in `specs/reference/technology/11-verification-queue.md`; if
   not, file it before writing code against it.
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
| `specs/reference/technology/` | Apple-framework API reference library (WWDC26 session notes, ✅/🟡/🔴 confidence markers). Companion to `memento-2.0-architecture-spec.md`; cited by `tech_refs:` in specs 013–022. Not itself an executable spec — read-only reference. |
| `docs/` | Engineering / how-it-works docs (RAG setup, CI policy, MEM-xx tickets) + hosted legal HTML. Unchanged, still authoritative for *how things work*. |
| `TESTFLIGHT_READINESS.md` (root) | **Superseded** by this folder (banner added). Kept as a historical record of pre-beta work completed in Oct 2025. |
| `.claude-instructions/` | Historical ad-hoc implementation plans. Read-only reference. |
| `.archive/APP_STORE_REJECTION_*.md` | Prior App Store rejection context — linked from spec 002. |
| `.sprints/` | Old sprint planning. Read-only reference. |

Status tracking lives **only** in spec front-matter + `ROADMAP.md`. No percentage
scores — they invite drift.
