# scripts/

- **`ci/`** — scripts invoked by GitHub Actions workflows (coverage gate, lint,
  periphery). These are live; changes affect CI.

### `ci/` — Memento 2.0 constitutional gate ladder

SDK-free governance gates run by `.github/workflows/spec-gates.yml`. Each
enforces one spec-derived rule continuously (bash/python, no Xcode). All pass on
the current tree; each was verified to fail on a planted violation.

| Script | Spec | Enforces | Mode |
|--------|------|----------|------|
| `check_single_intelligence_importer.sh` | 017 R1 (REQ-INT-001, P3) | ≤1 file imports `FoundationModels` | blocking |
| `lint_forbidden_phrases.py` | 014 R3 (REQ-POS-001) | no absolute-privacy claims in string literals / ASC metadata (comment-aware; `// REQ-POS-001-EXEMPT` opt-out) | blocking |
| `speakability_lint.py` | 018 R9 (REQ-VOX-006, P6) | no markdown/bullets/headings/emoji/URLs/blank-runs in spoken prose (`--selftest`, or pass generation files) | blocking (selftest) |
| `check_dependency_allowlist.sh` | 021 R6 (REQ-MON-005) | SPM deps ⊆ `specs/dependency-allowlist.txt` | report-only until spec 015 decommission; then `ALLOWLIST_ENFORCE=1` |
| `../Fixtures/validate_corpus.py` | 013 R4 / 016 R8 / 022 R1 | fixture corpus structure + honesty scrub + gold integrity; `corpus-validation` job also diffs `questions.resolved.json` for drift | blocking |

Making any of these a *required* status check is a branch-protection setting
(`docs/BRANCH_PROTECTION_SETUP.md`).

## Utility scripts (relocated from repo root by spec-001, 2026-07-13)

None of these are referenced by CI or docs. Verify against the current backend
before trusting them — several predate the RAG-era schema:

| Script | Purpose | Status |
|--------|---------|--------|
| `cleanup.sh` | Kill Xcode background services, deep-clean DerivedData | Dev convenience |
| `deploy-migrations.sh` | Old manual migration deploy | ⚠️ Likely stale — superseded by `.github/workflows/deploy-*.yml` |
| `DEPLOY_WEEKLY_QUESTIONS.sh` | Deploy "weekly question generation" system | ⚠️ Likely stale — relates to the dropped `follow_up_questions` feature |
| `TEST_QUESTIONS.sh` | Test the weekly-questions deployment | ⚠️ Likely stale (same feature) |
| `verify_preview_optimization.sh` | Check SwiftUI previews follow best practices | Dev convenience |
| `get-user-token.ts` | Deno: mint a user JWT for manually testing edge functions | Useful for specs 004/010 verification |
| `test-insights.ts` | Deno: exercise the generate-insights function | Useful for spec 004 verification |
