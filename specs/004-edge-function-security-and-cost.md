---
id: 004
title: Edge Function Security and LLM Cost Controls
tier: P1
status: not-started
effort: 2 sessions
depends_on: [003]
findings: [sync-embedding-unauthenticated, no-verify-jwt-config-drift, no-llm-rate-limiting, new-user-insights-limit-disabled, gemini-key-in-query-param, match-entries-caller-user-id, security-definer-search-path, shared-auth-dead-code, cors-wildcard-note]
---

# 004 — Edge Function Security and LLM Cost Controls

## Why

Every LLM endpoint (Gemini 2.5 Flash ×3, OpenAI gpt-4.1-nano ×1) is callable by any
authenticated user at unlimited rate — one abusive user or a leaked session drives
unbounded API spend. Worse, `sync-embedding` runs with the **service-role key and no
request authentication at all**. Public beta multiplies exposure: this must land before
external testers. Blocks **Gate 2**. Depends on 003 because RPC/schema hardening must
ship on a reproducible migration baseline.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | `sync-embedding` creates a `SUPABASE_SERVICE_ROLE_KEY` client and performs **no JWT or webhook-secret check**; re-embeds any `entryId` in the body. Header comment says deploy with `--no-verify-jwt` (`:9`) but neither `supabase/config.toml` nor `deploy-prod.yml:100-108` sets it → either it's an open service-role endpoint (quota burn + entry-existence oracle) or the documented webhook path silently fails and only the iOS direct-invoke path (`ChatService.swift:200-228`) works. | `supabase/functions/sync-embedding/index.ts:57-64,76-97` | HIGH |
| 2 | No per-user rate limit/quota on `chat`, `chat-with-entries`, `summarize-chat`, `generate-insights` — only pass-through of provider 429s (`chat-with-entries/index.ts:442`, `generate-insights/index.ts:248`). | those four functions | HIGH |
| 3 | `new-user-insights` ships `const RATE_LIMIT_HOURS = 0; // Disabled for testing` with the guard commented out, despite its header advertising 24h limiting. | `supabase/functions/new-user-insights/index.ts:33,166-173` | HIGH |
| 4 | Gemini API key sent as URL query param (`?key=…`) — leaks into proxy/access logs. Should be the `x-goog-api-key` header. | `chat/index.ts:188,235,611`; `chat-with-entries/index.ts:215,254,295`; `sync-embedding/index.ts:141`; `summarize-chat` | MEDIUM |
| 5 | `match_journal_entries` trusts a caller-supplied `match_user_id` param instead of `auth.uid()`, and has no explicit GRANT/REVOKE (EXECUTE defaults to PUBLIC/anon). RLS currently saves it (SECURITY INVOKER) — pin anyway for defense-in-depth. | `supabase/migrations/20260305000000_rag_chat_schema.sql:38-68`; called at `chat/index.ts:449` | LOW→MEDIUM |
| 6 | Several `SECURITY DEFINER` RPCs (stats/insights) don't pin `search_path`; only `delete_user` and remote-schema functions do. | `supabase/migrations/*.sql` | MEDIUM |
| 7 | `_shared/auth.ts` is dead code — every function duplicates inline JWT verification instead. Drift risk: a future function copies the wrong pattern. | `supabase/functions/_shared/auth.ts`; e.g. `chat/index.ts:295-310` | LOW |
| 8 | CORS is wildcard `*` everywhere (`_shared/cors.ts:21`, echoed inline per-function). Acceptable for a native-app-only API; document the decision. | `supabase/functions/_shared/cors.ts:21,33` | LOW (documented decision) |

## Requirements

### R1. No unauthenticated code path to any function
**Acceptance:** every function either verifies the caller's JWT or (webhook-style, i.e.
`sync-embedding`) verifies a shared secret header — regardless of gateway
`--no-verify-jwt` state; deploy config (`config.toml` / deploy workflows) matches each
function's documented mode; unauthenticated `curl` to every function returns 401.

### R2. Per-user rate limiting on every LLM endpoint
**Acceptance:** a shared, DB-backed limiter (e.g. a `request_log`/token-bucket table
keyed on `user_id, function, window` — RLS'd, service-role written) enforces sane
per-user limits on all four LLM functions (suggested starting points: chat 30 req/hr,
summarize 10/hr, generate-insights 4/day — tune freely); exceeding returns 429 with a
`retry_after`; limits are constants at the top of each function or a shared config;
`new-user-insights` 24h guard re-enabled.

### R3. Provider keys never in URLs
**Acceptance:** `grep -rn "key=\${" supabase/functions/` (and equivalents) → zero;
all Gemini calls use the `x-goog-api-key` header; OpenAI already uses Authorization.

### R4. RPC hardening
**Acceptance:** `match_journal_entries` derives the user from `auth.uid()` (parameter
removed or ignored-and-asserted), with explicit `REVOKE … FROM anon` + `GRANT … TO
authenticated`; every `SECURITY DEFINER` function sets `search_path`; all shipped as
migrations (on the spec-003 baseline).

### R5. One shared auth helper
**Acceptance:** `_shared/auth.ts` either becomes the single verifier imported by every
function, or is deleted and the inline pattern is documented in `_shared/README`;
no two functions carry divergent auth code.

## Out of Scope

- `chat` returning HTTP 200 on failure (error-contract fix) → **spec 010**.
- Decommissioning/keeping `chat-with-entries` → **spec 010** (decision recorded there;
  until then it gets rate-limiting + header fixes here like the others).
- CI deploy-pipeline integrity → **spec 006**.
- Prompt-injection hardening beyond current state — reviewed as LOW (self-targeted;
  citation filtering already prevents fabrication); revisit post-launch (spec 012).

## Tasks

- [ ] 1. Decide `sync-embedding` mode: (a) webhook w/ shared-secret header checked in
      code + `--no-verify-jwt` recorded in `supabase/config.toml`, or (b) user-JWT like
      the rest (iOS direct-invoke already sends one). Implement + align deploy config. (R1)
- [ ] 2. Create the rate-limit table migration + shared limiter helper in `_shared/`. (R2)
- [ ] 3. Wire the limiter into `chat`, `chat-with-entries`, `summarize-chat`,
      `generate-insights`; re-enable `new-user-insights` 24h guard. (R2)
- [ ] 4. Sweep all Gemini calls to `x-goog-api-key` header. (R3)
- [ ] 5. Migration: `match_journal_entries` → `auth.uid()`, explicit grants;
      `search_path` on all SECURITY DEFINER functions. (R4)
- [ ] 6. Consolidate on `_shared/auth.ts` (or delete + document). (R5)
- [ ] 7. Add Deno tests: limiter allows/blocks correctly; auth helper rejects
      missing/expired JWT. (R2/R5)
- [ ] 8. Client sanity pass: iOS handles a 429 from chat gracefully
      (`ChatService.swift` retry classifies 429 — confirm UX shows a friendly
      "slow down" message, not a crash or silent stall).

## Verification

- [ ] For each of the 7 functions: `curl -X POST <fn-url>` with no auth → 401.
- [ ] Scripted burst (limit+1 requests, valid JWT) against `chat` on staging → last
      request 429 with `retry_after`; iOS shows friendly copy.
- [ ] `new-user-insights` second call within 24h → 429/limited response.
- [ ] `grep -rn "key=" supabase/functions/ --include="*.ts" | grep -v x-goog` → no API
      keys in URLs.
- [ ] SQL: `SELECT proname, proconfig FROM pg_proc WHERE prosecdef` → every definer
      function shows `search_path` in proconfig.
- [ ] `deno test` suite green including new limiter/auth tests.

## Regression Guards

- **RLS intact** (CONSTITUTION §2): cross-user chat/RAG attempt still returns nothing.
- Citation filtering (`filterCitedIdsToAllowed`) untouched — RAG answers still cite
  only retrieved entries.
- `chat-feedback` ownership check still passes its flow.
- Embedding pipeline still works end-to-end after the sync-embedding auth change:
  new entry → embedding generated → retrievable in chat.
