---
id: 003
title: Database Baseline Reproducibility and Account Deletion
tier: P0
status: in-progress (2026-07-14) — repo work done; blocked on user: supabase db diff --linked and prod apply
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
| 3b | **(discovered 2026-07-13 during spec 002)** A **third** migrations directory was nested inside the app source folder at `MeetMemento/supabase/` (and shipping inside the app bundle!). Spec 002 relocated it verbatim to `supabase/UNRECONCILED-app-folder-copy/`. It contains 5 migrations **absent from the canonical dir**, including: `20260305000001_rename_entries_to_journal_entries.sql` — **the "missing" prod-only rename** (`entries→journal_entries`, `text→content`, +5 columns, soft-delete index) — plus `20260305000002_create_users_table.sql` (see row 4), `…03_create_ai_feedback_table.sql`, `…04_create_subscription_plans_table.sql`, and its own copy of `20260308000001_update_delete_user_rpc.sql`. These were very likely applied to prod by hand; reconciling THIS directory is most of R2's work. | `supabase/UNRECONCILED-app-folder-copy/migrations/` | HIGH |
| 4 | `delete_user()` runs `DELETE FROM public.users WHERE id = current_user_id;` and **no canonical migration** creates `public.users`. **REVISED 2026-07-13:** the nested dir's `20260305000002_create_users_table.sql` DOES create `public.users` (RLS'd, `ON DELETE CASCADE` from `auth.users`). If that migration was applied to prod (likely — its sibling rename clearly was), account deletion probably **works on prod today** and the true defect is reproducibility: fresh replays of the canonical chain lack both the table and the rename, so the RPC breaks only on rebuilt environments. **Verify against prod first** (`select to_regclass('public.users')`) before touching the RPC; the fix may be purely "adopt the nested migrations into the canonical chain". **RESOLVED 2026-07-14:** adopted as `20260304000001_create_users_table.sql`; `delete_user()` rewritten in `20260714000002_fix_delete_user_cascade_audit.sql`. Still needs the prod-side `select to_regclass('public.users')` check (task 5, user action) to confirm no drift. | `supabase/migrations/20260308000001_update_delete_user_rpc.sql:24`; `supabase/migrations/20260304000001_create_users_table.sql`; `supabase/migrations/20260714000002_fix_delete_user_cascade_audit.sql` | BLOCKER→**downgrade candidate** (verify on prod) |
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

## Cascade audit (Task 7 / R4)

Every user-owned table, verified against the canonical migration chain after
reconciliation. All 11 already carry `ON DELETE CASCADE` to `auth.users(id)` —
`delete_user()` (below) explicitly clears each anyway as defense-in-depth, with the
`auth.users` delete last as a backstop for anything future tables miss.

| Table | Cleared by |
|-------|------------|
| `chat_feedback` | explicit DELETE + FK CASCADE (`user_id`, and `message_id → chat_messages`) |
| `chat_messages` | explicit DELETE + FK CASCADE (`user_id`) |
| `chat_sessions` | explicit DELETE + FK CASCADE (`user_id`) |
| `journal_entries` | explicit DELETE + FK CASCADE (`user_id`) |
| `user_chat_caches` | explicit DELETE + FK CASCADE (`user_id`) |
| `user_insights` | explicit DELETE + FK CASCADE (`user_id`) |
| `user_stats` | explicit DELETE + FK CASCADE (`user_id` PK) |
| `user_profiles` | explicit DELETE + FK CASCADE (`user_id` PK) |
| `rate_limits` | explicit DELETE + FK CASCADE (`user_id`) — added by spec 004 |
| `ai_feedback` | explicit DELETE + FK CASCADE (`user_id`) |
| `public.users` | explicit DELETE + FK CASCADE (`id` PK) |
| `themes` | global reference data, not user-owned — excluded |
| `subscription_plans` | global reference data, not user-owned — excluded |
| `follow_up_questions` | dropped by `20251023000000_cleanup_deprecated_schema.sql` — not live, excluded |

## Implementation notes (2026-07-14)

- **R1/R2 reconciliation**: both stray directories are gone. `supabase_migrations/`
  (`001_create_journal_insights.sql` — dead table, zero app references, not adopted;
  `20260305_rag_chat_schema.sql` — an earlier draft fully superseded by canonical
  `20260305000000_rag_chat_schema.sql`, not adopted) and
  `supabase/UNRECONCILED-app-folder-copy/` (all 5 migrations adopted — see below).
- Four new idempotent migrations port the nested copy's content, timestamped
  `20260304000000-3` (before `20260305000000`, which already assumes the rename):
  rename `entries→journal_entries` (+columns), create `public.users`, create
  `ai_feedback`, create `subscription_plans`. `ai_feedback`/`subscription_plans` have
  live Swift models (`AIFeedback.swift`, `SubscriptionPlan.swift`) but **zero service
  call sites today** — adopted for reproducibility since they were deployed the same
  day as their siblings, but flagged in each migration's header to confirm against
  prod via `db diff --linked` and drop if prod doesn't actually have them.
  `public.users` and the rename are confirmed live (`UserService.swift`,
  `AuthViewModel.swift` query `.from("users")` constantly).
- The already-canonical `20260308000001_update_delete_user_rpc.sql` (which referenced
  the not-yet-existing `public.users`) is left untouched (never edit a shipped
  migration) — a new migration `20260714000002_fix_delete_user_cascade_audit.sql`
  supersedes it with the cascade-complete version below.
- **`supabase db reset` (local) verified clean** on 2026-07-14: all 29 migrations,
  including the 5 new ones, replayed with zero errors — "Finished supabase db reset
  on branch main." Local reproducibility (R2's first acceptance clause) is confirmed.
- **Not done, requires live prod credentials this session didn't have**:
  `supabase db diff --linked` (task 5), the prod apply (task 9), and the in-app
  end-to-end deletion test (task 8) against a real Auth-backed account. These are the
  remaining user actions before this spec can close.

## Tasks

- [x] 1. Inventory prod's real schema: `supabase db diff` / dashboard inspection; capture
      the authoritative current state (tables, columns, functions, policies).
      **Partial** — inferred from live Swift call sites + migration history rather than
      a live `db diff` (no prod credentials this session); see task 5.
- [x] 2. Reconcile **both** stray migration dirs against the canonical chain:
      `supabase_migrations/` (2 SQL files) **and**
      `supabase/UNRECONCILED-app-folder-copy/` (5 SQL files — likely the ones prod
      actually got; start here). Port anything real into `supabase/migrations/` with
      correct ordering + idempotency guards; then delete both stray dirs. (R1)
- [x] 3. Adopt the rename migration into the canonical chain: the nested copy
      (`…app-folder-copy/migrations/20260305000001_rename_entries_to_journal_entries.sql`)
      already contains the exact prod rename — port it **with idempotency guards**
      (guarded `ALTER TABLE ... RENAME`) so it is a no-op on prod but fixes fresh
      replays. Slot it with a timestamp *before* `20260305000000`. Do the same
      adoption analysis for the other four nested migrations. (R2)
- [x] 4. Iterate `supabase db reset` locally until the full chain replays clean. (R2)
- [ ] 5. Run `supabase db diff --linked` → resolve every drift item (each becomes either
      a migration or a documented intentional difference). **User action** (needs
      `supabase link` + prod DB password, not available in this session).
- [x] 6. Fix `delete_user()`: drop the `public.users` DELETE; explicitly handle every
      table from the R4 audit that lacks a verified cascade; keep
      `SECURITY DEFINER` + pinned `search_path`; ship as a new migration. (R3)
- [x] 7. Write the cascade-audit table into this spec. (R4)
- [ ] 8. End-to-end test on local/staging: create account → journal entries (incl. one
      with an embedding) → chat with feedback → delete account → assert zero rows
      per table + auth user gone. (R3) **User action** — needs a live Auth flow
      (email OTP / Apple sign-in) this session cannot drive.
- [ ] 9. Apply to prod via the manual `deploy-prod.yml` flow; re-run the in-app
      deletion test against prod with a throwaway account. **User action** — the
      workflow's typed confirmation is a deliberate human gate (spec 006).

## Verification

- [x] `supabase db reset` → exit 0, no errored statements in output. ✅ 2026-07-14
      (all 29 migrations applied clean, including the 5 new ones).
- [ ] `supabase db diff --linked` → no unexplained drift. **User action.**
- [x] `ls supabase_migrations 2>/dev/null` → gone; `git ls-files supabase_migrations/` → empty. ✅
- [ ] In-app account deletion on a seeded test account succeeds; SQL assertion script
      (commit it under `scripts/`) returns zero rows for the deleted user id across all
      user-owned tables; signing in with the deleted account no longer works.
      **User action.**
- [ ] Fresh clone + `supabase start` + `db reset` on a machine with no prior state
      reaches a working local stack (the true reproducibility test). **User action**
      (this session reused an already-running local stack rather than a fresh clone).

## Regression Guards

- **RLS on all 12 tables** (CONSTITUTION §2) must hold after every new migration —
  re-run a cross-user read attempt (user A cannot read user B's entries).
- `match_journal_entries` RPC and the HNSW embedding index must survive the replay —
  RAG chat still returns citations after `db reset` + reseed.
- The re-embed trigger on content change still fires (update an entry → embedding
  status resets).
