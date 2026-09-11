---
id: 042
title: Feedback Telemetry — Verification-Only Device Ingest
tier: P1
status: shippable (2026-09-11)
effort: 1 session
depends_on: [014, 019, 021, 022, 023, 041, 043]
findings:
  - feedback-is-write-only-on-device
  - no-remote-quality-signal
  - report-queue-has-no-triage-surface
  - live-warehouse-has-no-client
source_refs: [PRES-043, REQ-PRIV-001, REQ-EVAL-001, REQ-EVAL-005, REQ-MON-005]
supersedes:
  - "041 §Out of Scope — 'Remote / Supabase chat-feedback (violates REQ-PRIV-001)'"
  - "042 draft (2026-08-25) full live ingest into a feedback schema"
---

# 042 — Feedback Telemetry: Verification-Only Device Ingest

Ship volunteered in-app chat feedback — thumbs, “why” reasons, and
Report-for-review — to the existing live warehouse so
`public.answer_feedback` (`origin = device_human`) gets rows when a tester
opts in. Journal entries, chat history, and retrieval excerpts stay on
device. Leaving the device is allowed only for this verification pipeline,
not general sync or analytics.

---

## 0. What this slice is

The 2026-08-25 draft of this spec planned a dedicated `feedback` schema,
anonymous Supabase Auth, Slack webhooks, `pg_cron` retention, and a full
event ledger. **None of that exists on the live project.** What *is* live
(applied 2026-08-25 / 2026-08-27, currently empty of device rows):

- Project `ibdtqiembpexzeoyhfim` (`Memento-AI-Evaluations`)
- `public.answer_feedback` + `public.answer_feedback_queue` (041 local-triage
  shape, 043 origin/run_id)
- `public.import_answer_feedback(jsonb, text)` — **service-role / psql only**,
  not `SECURITY DEFINER`, revoked from `anon`/`authenticated`
- **No `feedback` schema. No live client.**

This amendment ships the smallest path that actually posts volunteered
feedback into that warehouse. Deferred pieces stay in §7.

### The five blockers, resolved for this slice

| # | Guard | Resolution |
|---|---|---|
| 1 | Empty `NSPrivacyCollectedDataTypes` | Manifest now declares Other User Content, Other Data Types, and User ID for the opt-in path. `check_privacy_manifest.sh` requires those types iff `SupabaseFeedbackClient.swift` exists |
| 2 | ENFORCING dependency allowlist | **No `supabase-swift`.** `URLSession` → PostgREST RPC |
| 3 | Published policy scrubbed of Supabase | `docs/privacy.html` and in-app Data Usage disclose the opt-in verification pipeline. Live GitHub Pages must be republished |
| 4 | `TrustZone` has no `.z2` | Feedback upload is **not** a `GenerationRequest`. Named `Z2ContentException` in spec 014 / CONSTITUTION §4 rule 8 |
| 5 | First third-party `URLSession` | Single client, write-only RPCs, absent-key no-op, consent off by default |

---

## 1. What leaves the device

| Signal | Local (041) | Remote when toggle is **on** |
|---|---|---|
| Thumbs up / down / undo | `AnswerFeedbackStore` | Metadata only |
| Why (category + note) | same row | Metadata (`note` is volunteered) |
| Report | `flaggedForReview = true` | Metadata; journal-derived `userPrompt` / `assistantReply` **only** if the reporter also flips “Include the question and answer for review” |

| Tier | Columns | Gate |
|---|---|---|
| `none` | nothing | **default** (toggle off, or missing keys) |
| `metadata` | rating, category, note, source, zone, model, prompt version, `was_degraded`, safety presentation, app version, citation **count**, timestamps, anonymous `device_id` | Settings toggle |
| `metadata_and_text` | the above + `user_prompt`, `assistant_reply` | toggle **and** per-report include-text switch |

Never sent: citation entry UUIDs, journal bodies, reflections, full chat
history. The on-device row may still hold prompt/reply/citation IDs; the
envelope redacts them. The RPC re-derives the text gate server-side so a
tampered client cannot store transcript text on a thumbs event.

---

## 2. Database (what actually shipped)

Migration: `supabase/migrations/20260911195100_device_verification_feedback.sql`

- `public.answer_feedback.device_id uuid` — erase key; null on warehouse/eval rows
- Stable `eval.run` labeled `device-verification-live` (`manual_device_session`)
- `public.submit_device_feedback(jsonb)` — `SECURITY DEFINER`, `search_path`
  pinned, granted `EXECUTE` to `anon`/`authenticated` only
- `public.erase_device_feedback(uuid)` — deletes `origin = device_human` rows
  for that `device_id` only

`import_answer_feedback` is unchanged and remains the manual-export path.

Write-only: no `SELECT`/`INSERT`/`UPDATE`/`DELETE` table grants for
`anon`/`authenticated`. RPCs return an integer count, never row bodies.
Supabase security advisors will WARN that anon can execute these
`SECURITY DEFINER` functions — that is the intended client path, not an
accident. Table RLS stays enabled with no policies (fail closed). A
2026-09-11 probe with the publishable anon key: submit HTTP 200, table
SELECT HTTP 401 (`permission denied`), erase HTTP 200.
Upsert is on `message_id` and refused unless `origin = device_human` and
`device_id` matches. Out-of-order updates (`updated_at` older) are ignored.
`flagged_for_review` is monotonic (`OR`).

Identity is an install-scoped UUID (`FeedbackDeviceIdentity`), created on
first consented enqueue. **No anonymous Auth and no Memento account**
(spec 023 stands). Anyone who knows a device UUID can erase that device’s
verification rows; UUIDs are unguessable and there is no read path.

---

## 3. Client

| File | Role |
|---|---|
| `FeedbackConsent.swift` | tier evaluation |
| `FeedbackEnvelope.swift` | redacting wire DTO |
| `FeedbackOutbox.swift` | durable JSON queue, `clientEventID` idempotency, 500-cap |
| `FeedbackDeviceIdentity.swift` | install UUID |
| `SupabaseFeedbackClient.swift` | `URLSession` → `submit_device_feedback` / `erase_device_feedback` |
| `FeedbackSyncService.swift` | enqueue → flush → backoff; tombstone erase |

Hooks: `ChatViewModel.persistFeedback` and `ChatService.submitFeedback`
write the local store first, then `record`. Network never blocks a thumb.
Flush on enqueue, `scenePhase == .active` / background, and launch.

`PreferencesService.shareFeedbackWithDeveloper` defaults **false** and is
cleared by `resetToDefaults()`. Settings → Your Data shows the toggle.
`ReplyFeedbackSheet` include-text switch appears only for Report when the
toggle is on (default off). Copy no longer claims the report always stays
on device when sharing is enabled.

---

## 4. Secrets

`SUPABASE_URL` and `SUPABASE_ANON_KEY` live in gitignored
`MeetMemento/Config/Supabase.xcconfig`, included from Debug/Release via
`#include?`. Committed example: `Supabase.xcconfig.example`. Surfaced
through `Info.plist`. **`service_role` must never appear in the app, repo,
or CI for the app target.** Missing or unexpanded keys → no-op; clones
build.

---

## 5. Erasure

`AppStateStore.deleteEverything()` and turning the toggle off call
`FeedbackSyncService.beginRemoteErase()` **before** local identity is
cleared. Offline / missing keys persist `erase-tombstone.json` and retry
on next launch. Outcome: `issued` / `queuedPending` / `skippedNoConsent` /
`skippedNoKeys`.

---

## 6. Compliance

### R1. Privacy model
Spec 014 records `Z2ContentException.answerFeedbackVerification`.
`TrustZone` keeps no `.z2` case. When 014 R4’s `NetworkCallSiteAudit` is
built, `SupabaseFeedbackClient` goes on the allowlist beside RevenueCat,
with the consent gate asserted in tests.

### R2. Privacy manifest
`PrivacyInfo.xcprivacy` declares the three types in §0. Tracking remains
false. `scripts/ci/check_privacy_manifest.sh` checks both directions
against the client file.

### R3. Store-facing copy
`docs/privacy.html`, Data Usage, and Settings disclose the opt-in path.
App Store Connect privacy labels must be updated before the next upload
(nutrition label is no longer “Data Not Collected” once this binary
ships). Republish GitHub Pages from `docs/privacy.html`.

### R4. Spec amendments
041 Out-of-Scope / REQ-PRIV-001 guard, PRES-043, 022 `REQ-EVAL-005`
narrowing, CONSTITUTION §4 rule 8, README, ROADMAP — this PR.

### R5. Dependency allowlist
Untouched because §3 declines the SDK.

---

## 7. Still out of scope

- `feedback` schema, anonymous Auth, `feedback.events` ledger, Slack /
  Database Webhooks, `pg_cron` 90-day text retention, `promote_device_feedback()`
- In-app review inbox; LLM-as-judge of reported answers
- Uploading journal entries, reflections, or full chat history
- Realtime, Storage, or any client read path
- Reinstating a Memento account
- Remote prompt / model configuration

---

## 8. Verification

**Unit**
- Consent `none` → no envelope
- `metadata` / report without include-text → `userPrompt` / `assistantReply` nil; no citation UUIDs
- Report + include-text → prompt/reply present; citation IDs still absent
- Missing keys → `record` enqueues nothing
- Outbox duplicate `clientEventID` is a no-op; retry keeps the same id
- Delete Everything captures `device_id` onto a tombstone before clearing it

**Live (tester)**
1. Copy `Supabase.xcconfig.example` → `Supabase.xcconfig` and fill the
   publishable anon key (Dashboard → Settings → API).
2. Settings → Your Data → **Share Quality Feedback** on.
3. Thumbs-down a reply and submit a reason → row in
   `public.answer_feedback` / `answer_feedback_queue` with empty
   `user_prompt` / `assistant_reply` and `origin = device_human`.
4. Report a reply with include-text on → those columns populated.
5. Toggle off or Delete Everything → that `device_id`’s rows are removed
   (or queued if offline).

**CI**
- `scripts/ci/check_privacy_manifest.sh`
- `scripts/ci/check_dependency_allowlist.sh` (no new package)
- `python3 scripts/ci/lint_forbidden_phrases.py`
- `scripts/ci/check_single_intelligence_importer.sh` still count = 1
