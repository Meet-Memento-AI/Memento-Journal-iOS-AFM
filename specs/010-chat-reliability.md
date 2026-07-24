---
id: 010
title: Chat Reliability and Error Contract
tier: P2
status: obsolete (2026-07-23)
effort: 1 session
depends_on: [004]
findings: [chat-200-on-failure, duplicate-chat-implementations, fire-and-forget-tasks]
---

# 010 — Chat Reliability and Error Contract

**Superseded by the Memento 2.0 rewrite — see spec
[019](019-surfaces.md). Left otherwise unmodified as historical record.**

## Why

The main `chat` edge function **returns HTTP 200 for every failure** — top-level
crashes and Gemini errors alike come back as a canned "sorry" body with status 200.
The iOS client's carefully built retry logic (`ChatService` retries 5xx/429/network)
therefore **never fires**, the user's message isn't persisted on the failure path, and
real outages are indistinguishable from the AI being unhelpful. Separately, two
divergent chat backends exist (`chat` = server-side RAG, trusted; `chat-with-entries` =
client-supplied grounding, weaker trust) — double maintenance and attack surface.
Gate 3, sequenced after 004 (shares the edge-function test harness and deploy loop).

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Top-level catch returns canned reply with **200** (`chat/index.ts:594-603`); Gemini failure path also 200 (`:481-489`). Client retry only triggers on 5xx/429/network (`ChatService.swift:140-166`) → never retries real failures; user message lost (not persisted on failure path). | `supabase/functions/chat/index.ts`, `MeetMemento/Services/ChatService.swift` | HIGH (within P2) |
| 2 | `chat-with-entries` (460 lines) duplicates the chat surface with client-supplied entries as grounding context (`chat-with-entries/index.ts:362-379`) — the client dictates what the LLM sees. Confirm whether the iOS app still calls it; decommission or explicitly justify. | `supabase/functions/chat-with-entries/` | MEDIUM |
| 3 | Fire-and-forget `Task {}` blocks in `ChatViewModel` (`:179,:374,:403`) aren't stored/cancelled — a rapidly dismissed chat view leaves in-flight work updating discarded state (bounded by @MainActor; not a leak, but wasted work and potential stale-state writes). | `MeetMemento/ViewModels/ChatViewModel.swift` | LOW |

## Requirements

### R1. Honest error contract
**Acceptance:** `chat` returns 5xx for infrastructure/LLM failures and 4xx for caller
errors, with a JSON error body (`{error, code, retryable}`); the graceful canned-reply
UX moves **client-side**: on a retryable failure the app shows the retry affordance and
**keeps the user's message in the input/thread** (not lost); on success-after-retry the
conversation persists normally. Transcript persistence on the server happens for the
user message even when generation fails (so history isn't silently missing turns).

### R2. One chat backend (or a documented reason for two)
**Acceptance:** determine live usage of `chat-with-entries` from the iOS codebase; if
unused → delete the function + its deploy entry; if used → migrate those call sites to
`chat` and then delete; if it must stay (e.g. a distinct feature genuinely needs
client-side context) → a header comment + note in this spec documents the trust
boundary and it gains the same rate-limit/auth hardening as the rest (from 004).

### R3. Cancellable view-model work
**Acceptance:** long-running tasks in `ChatViewModel` are stored (`Task` handles) and
cancelled in `onDisappear`/deinit-equivalent; sending a message then immediately
leaving the view doesn't corrupt the next session's state.

## Out of Scope

- Rate limiting / auth on chat functions → **spec 004** (done before this).
- Offline "needs connection" chat state → **spec 007**.
- Streaming responses (nice-to-have; park in **spec 012** if wanted).

## Tasks

- [ ] 1. Rework `chat/index.ts` error paths: correct status codes + structured error
      body; persist the user message before generation; keep the response-shape for
      success unchanged. (R1)
- [ ] 2. Update `ChatService.swift` to parse the error body and classify retryability;
      verify existing backoff kicks in. (R1)
- [ ] 3. `ChatViewModel`/`AIChatView`: failure keeps the user message visible with a
      retry affordance (reuse existing error-alert patterns). (R1)
- [ ] 4. Deno tests for the new error contract (error paths return non-200; success
      unchanged). (R1)
- [ ] 5. Grep iOS code for `chat-with-entries` invocations; execute the R2 decision
      tree; record the outcome here. (R2)
- [ ] 6. Store + cancel `ChatViewModel` tasks. (R3)

## Verification

- [ ] Force a Gemini failure on staging (invalid API key env var): iOS shows retry UI,
      message preserved; server log shows 5xx; restoring the key + tapping retry
      succeeds and the thread history contains the original message exactly once.
- [ ] `deno test` green including new error-contract tests.
- [ ] `grep -rn "chat-with-entries" MeetMemento/` matches only the decided outcome
      (zero if decommissioned).
- [ ] Rapid-fire: send message → back out of chat immediately → re-enter: no crash, no
      duplicated/stale messages.
- [ ] Happy path unchanged: normal chat with citations + thumbs feedback still works
      end-to-end.

## Regression Guards

- Citation filtering + JSON-schema-constrained output (CONSTITUTION §2) unchanged.
- Thumbs feedback flow (`chat-feedback`) unaffected by transcript-persistence changes.
- `ChatService` retry/backoff remains the single client retry mechanism — don't add a
  second loop in the view model.
