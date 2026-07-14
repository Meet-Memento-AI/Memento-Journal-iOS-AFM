# scripts/

- **`ci/`** — scripts invoked by GitHub Actions workflows (coverage gate, lint,
  periphery). These are live; changes affect CI.

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
