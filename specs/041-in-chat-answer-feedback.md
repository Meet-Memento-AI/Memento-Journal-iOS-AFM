---
id: 041
title: In-Chat Answer Feedback
tier: P2
status: complete (2026-08-24)
effort: 2 sessions
depends_on: [014, 019, 022]
findings:
  - session-only-thumbs
  - no-negative-reason-capture
  - no-report-overflow
  - feedback-backend-stub
source_refs: [PRES-043, REQ-PRIV-001, REQ-EVAL-001]
tech_refs: [technology/09-ui-swift6-testing.md]
---

# 041 — In-Chat Answer Feedback

**Traceability:** upgrades PRES-043's response action bar so every finished
assistant reply is a live quality sample. Spec [019](019-surfaces.md) owns
the Ask surface; spec [022](022-evaluation-and-quality-study.md) owns the
eval harness and may later consume this store. Spec
[014](014-privacy-model-and-trust-boundary.md) `REQ-PRIV-001` forbids
shipping transcripts or journal-derived text to Z2 — feedback stays
on-device.

Numbered 041 because [040](040-ipad-backend-readiness.md) already owns iPad
backend readiness.

## Why

Thumbs on the action bar are session decoration: `ChatViewModel` keeps sets
in memory and `ChatService.submitFeedback` is a no-op after the old
`chat-feedback` backend was removed. There is no way to say why an answer
failed, and no overflow to flag a turn for human review. Turning the chat
UI into a continuous testing environment needs three stored signals on the
same row: positive (thumbs up), negative with a reason (thumbs down plus
sheet), and explicit report-for-review (overflow).

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Thumbs do not survive relaunch | `ChatService.submitFeedback` logs and returns the type; `fetchFeedback` always empty | P1 |
| 2 | Thumbs down writes immediately with no reason | `ChatViewModel.toggleThumbsDown` inserts the id then fire-and-forgets | P1 |
| 3 | No overflow / Report answer | `AIOutputComponent` action HStack ends at regenerate | P1 |
| 4 | Hard-refuse, empty-observation, markdown fallback have no report chrome | `ChatMessageBubble.messageContent` branches | P2 |
| 5 | PRES-043 still says persisted thumbs | `specs/reference/frontend-preservation-contract.md` | P2 |

## Requirements

### R1. Overflow on every finished assistant reply

Native SwiftUI `Menu`, last item in the existing action HStack. SF Symbol
`ellipsis`, 14pt bold, `theme.mutedForeground`, min hit box 28pt. Menu
item: **Report answer**. Appears with the bar (has content and not
streaming). Also on markdown fallback, empty-observation (next to Try
again), and hard-refuse. Not on crisis cards or user bubbles. Regenerates
stays last-reply-only; overflow is on every finished assistant turn.

**Acceptance:** a finished assistant reply shows More; a streaming reply
does not; a crisis card does not.

### R2. Thumbs up is stored positive feedback

One tap fills `hand.thumbsup.fill` / accent, clears thumbs down, writes
`rating = positive` immediately. Second tap undoes (`rating = none`). No
what-went-right sheet.

**Acceptance:** thumbs up is filled after tap and still filled after
`loadFeedbackForMessages` on a store that has the row.

### R3. Thumbs down opens a reason sheet; persist only on Submit

First tap does not fill the icon and does not write. Opens
`ReplyFeedbackSheet` in `.thumbsDown` mode. Cancel / dismiss: no store
write, icon stays outline. Pressing Submit fills `hand.thumbsdown.fill` /
destructive, writes `rating = negative` plus category plus optional note,
and shows a toast. Pressing an already-negative thumb undoes without
reopening the sheet.

**Acceptance:** opening the sheet then cancelling leaves rating empty;
Submit without a category is disabled; Submit writes negative plus
category.

### R4. One sheet, two sources

Shared `ReplyFeedbackSheet` presented once from `AIChatView` via
`feedbackDraft` (not per-bubble). Detent medium. Title thumbs-down: "What
went wrong?"; report: "Report answer". Required single-select chips:
Wrong recall, Made something up, Didn't answer, Tone, Safety, Other.
Optional note, about 280 chars. Primary disabled until a category is
selected. Report on an already-downvoted message pre-fills category/note.
Subtitle discloses that the report stays on this device.

**Acceptance:** both entry points present the same sheet; report copy
differs; prefill works when a negative row already exists.

### R5. One AnswerFeedback row per messageID

Fields: rating (none / positive / negative), flaggedForReview, category,
note, source, userPrompt, assistantReply, citationEntryIDs (IDs only — no
excerpts), promptVersion, modelIdentifier, zone, wasDegraded,
safetyPresentation, appVersion, timestamps.

| Action | rating | flaggedForReview | category/note |
|---|---|---|---|
| Thumbs up | positive | unchanged | cleared |
| Thumbs down submitted | negative | unchanged | from sheet |
| Thumbs down undone | none | unchanged | cleared unless still reported |
| Report submitted | unchanged | true | from sheet (or keep) |
| Clear thumbs up | none | unchanged | — |

A reply may be both negative and reported.

**Acceptance:** report on a downvoted message keeps the rating and sets
the flag; payload has no citation excerpts.

### R6. On-device store, restore on load

`AnswerFeedbackStore` JSON under Application Support (mirror
`LocalChatStore`). No network. `loadFeedbackForMessages()` restores filled
thumbs and Reported overflow after relaunch. Delete Everything (spec 023)
clears the store. Journal bodies are not copied into reports.

**Acceptance:** a temp-directory store round-trips a row.

### R7. Copy and a11y

Sheet discloses on-device storage. Identifiers: `chat.reply.thumbsUp`,
`chat.reply.thumbsDown`, `chat.reply.more`, `chat.reply.report`,
`chat.feedback.category.<id>`, `chat.feedback.submit`. Overflow after
report: ellipsis accent, menu row disabled **Reported**.

### R8. Export hook (thin)

Include rated/reported answers in the existing Settings journal export
when any rows exist. No in-app review inbox.

## Out of Scope

- Remote / Supabase `chat-feedback` (violates REQ-PRIV-001)
- LLM-as-judge; in-app review queue (spec 022)
- Thumbs-up reason; auto-opening the sheet from thumbs down after a delay
- Crisis-card overflow
- Changing regenerate rules

## Tasks

- [x] 1. Write this spec; amend PRES-043, ROADMAP, README (040 is taken, this is 041)
- [x] 2. Overflow Menu plus isReported / onReportAnswer through AIOutputComponent, ChatMessageBubble, ChatMessagesView; attach chrome to fallback / refuse / empty-observation
- [x] 3. ReplyFeedbackSheet; present from AIChatView via feedbackDraft; thumbs down opens sheet and only fills on Submit; Report uses same sheet
- [x] 4. AnswerFeedbackStore JSON; restore thumbs plus reported on load; snapshot turn metadata without journal bodies; Delete Everything clears
- [x] 5. Store / view-model tests; a11y identifiers; Settings export hook

## Verification

- [x] Finished reply shows More; streaming hides More (`showsActionBar = hasRenderableContent && !isStreaming`; overflow lives in that bar)
- [x] Thumbs up fills accent; store reload still filled (`test_thumbsUp_persistsPositive`, `test_loadSession_restoresThumbsAndReported`)
- [x] Thumbs down opens sheet; Submit without category disabled; Cancel leaves outline and no row (`test_thumbsDown_doesNotPersistUntilSubmit`; sheet Submit `.disabled(!canSubmit)`)
- [x] Submit down fills plus stored negative plus category (`test_thumbsDown_submitPersistsNegativeAndCategory`)
- [x] Report uses the same sheet with report copy; after submit, menu shows Reported (`ReplyFeedbackSheet` report title; `ReplyOverflowMenu` disables **Reported**)
- [x] Store file contains prompt/reply/promptVersion when present; no citation excerpts (`test_thumbsUp_persistsPositive`, `test_payload_omitsCitationExcerpts`)
- [x] Crisis card has no overflow (`ChatMessageBubble` crisis branch renders `CrisisResourceCard` only)
- [x] Delete Everything removes the feedback file (`test_deleteEverything_clearsAnswerFeedback`, `AnswerFeedbackStoreTests.test_clear_removesRows`)

## Regression Guards

> **Amended 2026-08-27 (spec [043](043-eval-run-warehouse.md)).** The
> warehouse copy of this row in `public.answer_feedback` gains an `origin`
> label and a `run_id`, and relaxes two constraints so non-device judgments can
> share the table: `source` and `message_id` become nullable, and `message_id`
> uniqueness becomes a partial index over non-null values. The on-device store
> and R5's one-row-per-`messageID` rule are unchanged, and the CHECK
> `device_rows_keep_041_shape` holds every `origin = 'device_human'` row to the
> original contract. REQ-PRIV-001 is unaffected: 043 stores synthetic fixture
> data and developer/LLM critique only.



- PRES-043 action bar still hidden while streaming
- Regenerates still last-reply-only
- Crisis card (spec 026) unchanged — no overflow, no thumbs
- REQ-PRIV-001: no Z2 upload of prompt, reply, or journal text
- Action bar layout (HStack spacing 8, top padding 8) must not reintroduce
  the empty-placeholder gap above "Memento is thinking"
