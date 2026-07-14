---
id: 003
title: Database Baseline Reproducibility and Account Deletion
tier: P0
status: not-started
effort: 2 sessions
depends_on: []
findings: [migrations-not-reproducible, prod-only-table-rename, dual-migrations-dirs, delete-user-rpc-broken, cascade-coverage-unverified, reconcile-noop-migration]
---

# 003 — Database Baseline Reproducibility and Account Deletion

## Why

Two compounding problems. First, the migration set **cannot build a database from
scratch**: early migrations create a table named `entries`, later ones assume
`journal_entries` (with a `content` column vs the old `text`), and **no migration
performs the rename** — it was hand-applied to prod only. Fresh `supabase db reset`,
new staging environments, reviewer-local setups, and disaster recovery are all broken.
Second, the `delete_user()` RPC deletes from a **non-existent `public.users` table**
inside an all-or-nothing block — so in-app account deletion throws and rolls back.
Apple guideline **5.1.1(v)** requires working account deletion for apps with accounts;
this alone is an App Store rejection, and it's a GDPR problem besides. Blocks **Gate 1**.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Early migrations create/operate on `entries` (`20250117000000_create_entries_table.sql:9`, `20251021124456_remote_schema.sql:1-15`, `20251023000002_add_data_validation.sql:12+`); from `20260305000000_rag_chat_schema.sql:19` onward everything targets `journal_entries.content`. `grep -ri RENAME supabase/migrations/` → nothing. Fresh replay fails at `20260305000000` with `relation "journal_entries" does not exist`. | `supabase/migrations/` | BLOCKER |
| 2 | `20260422201548_reconcile_remote_history.sql` is an intentional no-op (`select 1`) whose comment admits "a production-only migration history entry … applied outside this repository". | `supabase/migrations/20260422201548_reconcile_remote_history.sql` | evidence of #1 |
| 3 | **Second, divergent migrations directory tracked at repo root**: `supabase_migrations/{001_create_journal_insights.sql, 20260305_rag_chat_schema.sql, README.md}` — overlaps/diverges from the canonical `supabase/migrations/`. | `supabase_migrations/` (git-tracked) | HIGH |
| 4 | `delete_user()` runs `DELETE FROM public.users WHERE id = current_user_id;` but no migration creates `public.users` (only `auth.users` + `user_profiles` exist). The surrounding exception block makes the whole RPC raise and roll back → account deletion deletes nothing. | `supabase/migrations/20260308000001_update_delete_user_rpc.sql:24` (block `:19-34`) | BLOCKER (5.1.1(v) / GDPR) |
| 5 | `delete_user()` explicitly clears only `journal_entries`, `chat_messages`, `chat_sessions`, relying on `auth.users` CASCADE for the rest. Cascade coverage for `chat_feedback`, `user_stats`, `user_insights`, `user_chat_caches`, `user_profiles`, `themes` is unverified. | same file; table DDLs across `supabase/migrations/` | HIGH |
| 6 | Ad-hoc SQL applied outside migrations historically — archived by spec 001 to `.archive/adhoc-sql/`. **Content summary (recorded 2026-07-13 before archiving):** `SETUP_JOURNAL_ENTRIES.sql` was dashboard-run SQL that created `public.entries` (columns incl. `text TEXT NOT NULL`), its 4 RLS policies, `get_user_entry_count()`, `get_user_entry_stats()` (both `SECURITY DEFINER` with `search_path` set), and the `update_entries_updated_at` trigger + `update_updated_at_column()` function. `DELETE_USER_SQL.sql` was an **earlier** dashboard-run `delete_user()` that deleted from `public.entries` + `auth.users` only — it did NOT reference `public.users`; that broken reference arrived later in migration `20260308000001`. Both prove prod schema was partly built via SQL Editor, outside migrations — exactly the drift R2's diff must reconcile (check whether `get_user_entry_count`/`get_user_entry_stats`/the trigger exist in prod but not in migrations). | `.archive/adhoc-sql/` | context |
| 7 | dev/staging deploys mask migration errors, so this breakage is invisible in CI (grep-swallow — owned by spec 006, but be aware while testing here). | `.github/workflows/deploy-dev-staging.yml:105-112` | context |

## Requirements

### R1. One canonical migrations directory
**Acceptance:** `supabase_migrations/` is gone; anything it contained that prod actually
has is represented in `supabase/migrations/`; a README note in `supabase/migrations/`
states it is the only migrations home (standing rule 2 in CONSTITUTION.md).

### R2. Fresh database replay succeeds and matches prod
**Acceptance:** `supabase db reset` (local) completes with zero errors; the resulting
schema is diffed against prod (`supabase db diff --linked`) and shows **no relevant
drift** (table names, columns, functions, triggers, indexes, policies).
The `entries → journal_entries` rename (and `text → content`, plus any other
prod-only changes the diff reveals) exists as a real, ordered migration.

### R3. Account deletion works end-to-end
**Acceptance:** from the app UI, deleting an account (a) succeeds without error,
(b) removes the `auth.users` row, and (c) leaves **zero rows for that user in every
user-owned table** (journal_entries, chat_sessions, chat_messages, chat_feedback,
user_profiles, user_stats, user_insights, user_chat_caches, themes, and any others the
audit in R4 finds). The fixed RPC ships as a new migration.

### R4. Cascade audit documented
**Acceptance:** a table in this spec lists every user-owned table and how it is cleared
on deletion (explicit DELETE in RPC vs `ON DELETE CASCADE` FK vs trigger), each verified
by the R3 test.

## Out of Scope

- Fixing the CI grep-swallow that hides migration failures → **spec 006** (but R2's
  local verification doesn't depend on CI).
- Edge-function/RPC security hardening (`search_path`, `auth.uid()` pinning) → **spec 004**.
- Removing the ad-hoc SQL files from root → **spec 001** (content preserved as evidence).

## Tasks

- [ ] 1. Inventory prod's real schema: `supabase db diff` / dashboard inspection; capture
      the authoritative current state (tables, columns, functions, policies).
- [ ] 2. Reconcile `supabase_migrations/`: diff its 2 SQL files against canonical
      migrations; port anything real; delete the directory. (R1)
- [ ] 3. Write the missing baseline migration(s) capturing the prod-only rename
      (`entries→journal_entries`, `text→content`) **idempotently** (guarded
      `ALTER TABLE ... RENAME`) so it is a no-op on prod but fixes fresh replays.
      Slot it with a timestamp *before* `20260305000000`. (R2)
- [ ] 4. Iterate `supabase db reset` locally until the full chain replays clean. (R2)
- [ ] 5. Run `supabase db diff --linked` → resolve every drift item (each becomes either
      a migration or a documented intentional difference). (R2)
- [ ] 6. Fix `delete_user()`: drop the `public.users` DELETE; explicitly handle every
      table from the R4 audit that lacks a verified cascade; keep
      `SECURITY DEFINER` + pinned `search_path`; ship as a new migration. (R3)
- [ ] 7. Write the cascade-audit table into this spec. (R4)
- [ ] 8. End-to-end test on local/staging: create account → journal entries (incl. one
      with an embedding) → chat with feedback → delete account → assert zero rows
      per table + auth user gone. (R3)
- [ ] 9. Apply to prod via the manual `deploy-prod.yml` flow; re-run the in-app
      deletion test against prod with a throwaway account.

## Verification

- [ ] `supabase db reset` → exit 0, no errored statements in output.
- [ ] `supabase db diff --linked` → no unexplained drift.
- [ ] `ls supabase_migrations 2>/dev/null` → gone; `git ls-files supabase_migrations/` → empty.
- [ ] In-app account deletion on a seeded test account succeeds; SQL assertion script
      (commit it under `scripts/`) returns zero rows for the deleted user id across all
      user-owned tables; signing in with the deleted account no longer works.
- [ ] Fresh clone + `supabase start` + `db reset` on a machine with no prior state
      reaches a working local stack (the true reproducibility test).

## Regression Guards

- **RLS on all 12 tables** (CONSTITUTION §2) must hold after every new migration —
  re-run a cross-user read attempt (user A cannot read user B's entries).
- `match_journal_entries` RPC and the HNSW embedding index must survive the replay —
  RAG chat still returns citations after `db reset` + reseed.
- The re-embed trigger on content change still fires (update an entry → embedding
  status resets).
