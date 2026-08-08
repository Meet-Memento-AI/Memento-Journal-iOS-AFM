# scripts/

- **`ci/`** — scripts invoked by GitHub Actions workflows (coverage gate, lint,
  periphery, governance gates). These are live; changes affect CI.

### `ci/` — invoked by CI

| Script | Workflow | Enforces | Mode |
|--------|----------|----------|------|
| `lint_changed_swift.sh` | `ios-tests.yml` | SwiftLint on changed files (incl. `no_print`) | blocking (PR) |
| `check_coverage.sh` | `ios-tests.yml` | global line-coverage floor (`MIN_COVERAGE`, ratchet-only) | blocking |
| `check_periphery_regression.sh` | `ios-tests.yml` | no new dead-code findings in changed files | blocking (PR) |
| `check_single_intelligence_importer.sh` | `spec-gates.yml` | **exactly one** file imports `FoundationModels` | blocking |
| `lint_forbidden_phrases.py` | `spec-gates.yml` | no absolute-privacy claims (comment-aware; `// REQ-POS-001-EXEMPT` opt-out) | blocking |
| `speakability_lint.py` | `spec-gates.yml` | no markdown/bullets/emoji/URLs in spoken prose (`--selftest`) | blocking (selftest) |
| `check_dependency_allowlist.sh` | `spec-gates.yml` | SPM deps ⊆ `specs/dependency-allowlist.txt` | report-only (supabase-swift still used by the two live edge functions) |
| `../Fixtures/validate_corpus.py` | `spec-gates.yml` | fixture corpus structure + honesty scrub + gold integrity | blocking |

Making any of these a *required* status check is a branch-protection setting
(`docs/BRANCH_PROTECTION_SETUP.md`).

The Release-endpoint assertion (spec-006 R3) is **inlined into the Xcode Release
build phase** in `MeetMemento.xcodeproj/project.pbxproj` (to stay inside Xcode's
user-script sandbox) — there is no standalone `ci/assert_release_endpoint.sh`.

## Utility scripts (dev-only, not referenced by CI)

| Script | Purpose | Status |
|--------|---------|--------|
| `cleanup.sh` | Kill Xcode background services, deep-clean DerivedData | Dev convenience |
| `deploy-migrations.sh` | Manual migration deploy | ⚠️ Superseded by `.github/workflows/deploy-*.yml`; keep only for local hacking |
| `verify_preview_optimization.sh` | Check SwiftUI previews follow best practices | Dev convenience |

Scripts tied to retired features (weekly-questions / server-side chat / insights
poking) were removed when chat, summarization, and embeddings moved on-device.
Recover them from git history if needed; do not point dev scripts at production.
