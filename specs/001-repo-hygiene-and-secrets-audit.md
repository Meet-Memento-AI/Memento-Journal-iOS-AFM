---
id: 001
title: Repo Hygiene and Secrets Audit
tier: P0
status: done (2026-07-13)
effort: 1 session
depends_on: []
findings: [dead-secrets-file, coverage-artifact-untracked, root-clutter, adhoc-sql-files, embedded-worktree-repo]
---

# 001 — Repo Hygiene and Secrets Audit

## Why

Before the first TestFlight archive, the repo needs one hygiene pass: confirm no
credentials are tracked, remove dead credential files, and clear root-level clutter
(loose SQL/scripts/zips) that is both submission noise and evidence of ad-hoc SQL
applied outside migrations (the deeper problem spec 003 fixes). Doing this first also
gives specs 002–006 a clean surface: nothing they touch should collide with junk files.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | `MeetMemento/Secrets.swift` holds a real Supabase project URL + anon key. **Verified NOT tracked and never committed** (`git log --all --follow` empty; ignored at `.gitignore:106`). Dead code — zero `Secrets.` references in the app; runtime uses the xcconfig path. | `MeetMemento/Secrets.swift:12-13` | LOW (hygiene — anon key is public-by-design, RLS-protected) |
| 2 | Untracked Deno coverage artifact with no ignore rule — one careless `git add -A` away from being committed. | `supabase/functions/chat/coverage/` (html/lcov/json) | LOW |
| 3 | Root-level clutter: `Sora.zip`, `Sora_test.zip`, `cleanup.sh`, `DEPLOY_WEEKLY_QUESTIONS.sh`, `deploy-migrations.sh`, `TEST_QUESTIONS.sh`, `verify_preview_optimization.sh`, `get-user-token.ts`, `test-insights.ts` | repo root (`ls *.zip *.sh *.ts`) | MEDIUM |
| 4 | Ad-hoc SQL files at root — evidence of SQL applied to prod outside migrations: `DELETE_USER_SQL.sql`, `SETUP_JOURNAL_ENTRIES.sql` | repo root | MEDIUM (content feeds spec 003) |
| 5 | Embedded git repository accidentally addable: `.claude/worktrees/practical-khorana` (git warned about it during the 2026-07-13 merge). `.scannerwork/` (Sonar scratch) also untracked with no ignore rule. | `.claude/`, `.scannerwork/` | LOW |

## Requirements

### R1. No credentials in tracked files, verified exhaustively
**Acceptance:** `git ls-files | xargs grep -lE "supabase\.co|eyJ[A-Za-z0-9_-]{20,}"`
returns only legitimate matches (docs/templates with placeholders, this specs folder);
`git ls-files | grep -i secret` returns nothing; gitleaks (already in `security.yml`)
passes locally.

### R2. Dead credential file removed
**Acceptance:** `MeetMemento/Secrets.swift` deleted from disk (it is unreferenced);
app still builds. The `.gitignore:106` rule stays (protects against recreation).

### R3. Generated artifacts ignored
**Acceptance:** `.gitignore` covers `coverage/` (function test output),
`.scannerwork/`, and `.claude/worktrees/`; `git status` shows none of them.

### R4. Root directory contains only project files
**Acceptance:** zips deleted (or moved to `.archive/` if they matter); loose `.sh`/`.ts`
utilities moved to `scripts/` (join the existing `scripts/ci/`); the two ad-hoc `.sql`
files moved to `.archive/adhoc-sql/` **after** confirming spec 003 has captured their
content (they are its evidence — do not destroy before 003 reads them).

## Out of Scope

- Making migrations reproducible / reconciling `supabase_migrations/` → **spec 003**
  (the dual-directory problem is a schema-integrity issue, not file clutter).
- Anon-key rotation: not required (anon keys are designed to ship in clients and the
  file never entered git history). If rotation is ever desired, do it alongside
  spec 004's backend work.
- CI enforcement of secret scanning cadence → **spec 006**.

## Tasks

- [x] 1. Run the R1 secrets sweep across tracked files; record results in this spec.
- [x] 2. Delete `MeetMemento/Secrets.swift`; remove its `project.pbxproj` file reference
      if one exists (there was none — 0 refs); build to confirm no breakage. (R2)
- [x] 3. Add `.gitignore` entries: `supabase/functions/**/coverage/`, `.scannerwork/`,
      `.claude/worktrees/`. (R3)
- [x] 4. Confirm spec 003's status. 003 not started → SQL content summarized into spec
      003's evidence row 6 (2026-07-13), then both files moved to `.archive/adhoc-sql/`. (R4)
- [x] 5. `Sora.zip` / `Sora_test.zip` deleted — both were **corrupt** (unzip: no
      end-of-central-directory) and the Sora fonts are already installed at
      `MeetMemento/Resources/Fonts/Sora-*.ttf`. Seven loose scripts moved into
      `scripts/` with a provenance/staleness table in `scripts/README.md`. (R4)
- [x] 6. Commit as a single hygiene commit referencing `[spec-001]`.

## Sweep results (Task 1, run 2026-07-13)

- Tracked filenames matching `secret` → **none**.
- JWT-shaped strings (`eyJ…`) in tracked files → exactly two, **both verified
  placeholders by decoding their payloads**:
  - `MeetMemento/Services/SupabaseService.swift:49` → `{"iss":"supabase","ref":"local","role":"anon"}` (intentional fallback)
  - `.github/workflows/ios-tests.yml:41,46` → `{"ref":"ci","role":"anon"}` (CI stub)
- `sk-…` / `AIza…` provider-key patterns → **none**.
- Supabase URLs in tracked files → placeholders (`example`, `placeholder`, `invalid`,
  `xxxxx`, `app`) plus the real project ref `fhsgvlbedqwxwpubtlls` appearing **only in
  historical docs** (`.archive/`, `.claude-instructions/` — ~20 hits). Assessment:
  the project URL/ref is a public identifier (it ships inside every app binary and in
  every API request); leaving it in historical docs is acceptable. No live key
  accompanies it anywhere tracked.
- `MeetMemento/Secrets.swift` (the only real-key file) — re-confirmed via
  `git ls-files --error-unmatch` + `git log --all`: **never tracked, never committed**;
  deleted from disk. Note: an earlier report that it was tracked came from misreading
  `git check-ignore` output (which echoes matching ignored paths).

## Verification

- [x] `git ls-files | grep -iE "secret|\.zip$"` → empty. ✅ 2026-07-13
- [x] `git ls-files | xargs grep -lE "eyJ[A-Za-z0-9_-]{40,}" 2>/dev/null` → only the two
      decoded-and-confirmed placeholders (`ref:"local"`, `ref:"ci"`). ✅
- [x] `git status --porcelain` shows no coverage/`.scannerwork`/worktree artifacts
      (ignore rules verified). ✅
- [x] `ls *.sh *.ts *.sql *.zip 2>/dev/null` at repo root → empty. ✅
- [x] `xcodebuild -scheme MeetMemento -destination 'platform=iOS Simulator,name=iPhone 17' build`
      → BUILD SUCCEEDED after `Secrets.swift` deletion. ✅

## Regression Guards

- Config loading (xcconfig → Info.plist → `SupabaseService`) untouched — the app must
  still resolve `SUPABASE_URL`/`SUPABASE_ANON_KEY` from `*.local.xcconfig`.
- Do not delete `MeetMemento/Config/*.template` files — they are the documented setup path.
