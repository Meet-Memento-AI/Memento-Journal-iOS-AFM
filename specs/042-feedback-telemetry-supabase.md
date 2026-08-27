---
id: 042
title: Feedback Telemetry — Supabase Ingestion
tier: P1
status: draft (2026-08-25)
effort: 3–4 sessions
depends_on: [014, 019, 021, 022, 023, 041]
findings:
  - feedback-is-write-only-on-device
  - no-remote-quality-signal
  - report-queue-has-no-triage-surface
source_refs: [PRES-043, REQ-PRIV-001, REQ-EVAL-001, REQ-EVAL-005, REQ-MON-005]
supersedes:
  - "041 §Out of Scope — 'Remote / Supabase chat-feedback (violates REQ-PRIV-001)'"
---

# 042 — Feedback Telemetry: Supabase Ingestion

Ship every answer-feedback signal — thumbs up, thumbs down, the reason
("why"), the free-text note, and Report-for-review — to Supabase the moment
it is created, organized for both machine rollups and human triage.

---

## 0. Read this before anything else

**This spec deliberately reverses a decision the repo ratified one day ago.**
Spec 041 (`status: complete (2026-08-24)`) lists *"Remote / Supabase
`chat-feedback`"* under **Out of Scope** with the reason *"violates
`REQ-PRIV-001`"*, and carries the regression guard *"`REQ-PRIV-001`: no Z2
upload of prompt, reply, or journal text."* `AnswerFeedbackStore.swift`'s
header comment says *"Never leaves the device (REQ-PRIV-001)."* Spec 014's
`TrustZone` enum has **no `.z2` case** — by design, so that "a type that
could represent Z2-tagged content" cannot exist.

That is the user's call to reverse, and this spec plans the reversal in
full. But it is not a database task with a privacy footnote: it is a
privacy-posture change with a database attached, and five mechanical guards
in this repo will stop a naive implementation at CI or at App Store review.
§7 handles each one. **Nothing in §1–§6 is shippable without §7.**

The design below is built so the reversal is *defensible*: consent is
explicit and off by default, journal-derived text is separated from
volunteered feedback and gated independently, the client can never read
anything back, and Delete Everything erases the server side too.

### The five blockers, up front

| # | Guard | Where | What breaks |
|---|---|---|---|
| 1 | `NSPrivacyCollectedDataTypes` is an **empty array**, commented *"the app is on-device only… never transmitted off it"* | `PrivacyInfo.xcprivacy` | `scripts/ci/check_privacy_manifest.sh` checks **both directions** — CI fails |
| 2 | Dependency allowlist runs **ENFORCING** (`ALLOWLIST_ENFORCE=1`) and records `supabase/supabase-swift` as decommissioned | `specs/dependency-allowlist.txt`, `.github/workflows/spec-gates.yml` | Adding the SDK fails CI. §5 avoids the SDK entirely |
| 3 | Published privacy policy was scrubbed of Supabase on 2026-08-17 and the readiness item closed on *"no OpenAI/Supabase/Gemini"* | `docs/app-store/00-readiness-checklist.md` B2 | Guideline 5.1.1(i) / 5.1.2(i) exposure |
| 4 | `TrustZone` has no Z2 case; spec 014 R4 plans a `NetworkCallSiteAudit` asserting every call site is Z0/Z1 or the RevenueCat exception | `specs/014` R1/R4 | New call site is an unclassifiable fourth category |
| 5 | The app currently has **zero `URLSession` call sites** | verified by grep across `MeetMemento/` | This spec introduces the app's first third-party network call. It should look like it was designed, not slipped in |

There is precedent for a sanctioned Z2 exception — RevenueCat (spec 021).
But that exception is explicitly *"receipts + anonymous ID only — never
carries content."* Feedback carries `userPrompt` and `assistantReply`,
which are journal-derived. So this is a **new class** of exception, and §7
R1 records it as one rather than pretending it fits the existing carve-out.

---

## 1. What gets sent

Four signals, all already modelled on-device by spec 041's `AnswerFeedback`:

| Signal | Today (on-device) | Sent as |
|---|---|---|
| **Positive** | `rating = .positive`, `source = .thumbsUp` | event `thumbs_up` + current-state upsert |
| **Negative** | `rating = .negative`, `source = .thumbsDown` | event `thumbs_down` + upsert |
| **Why** | `category` (6 cases) + `note` (~280 chars) | columns on both event and current-state |
| **Report** | `flaggedForReview = true`, `source = .report` | event `report` + upsert + **auto-opened triage row** |
| *Undo* | `rating = .none` | events `thumbs_up_undo` / `thumbs_down_undo` |

### 1.1 Two consent tiers, because two kinds of text

The distinction that makes this defensible:

- **`note` is volunteered.** The user typed it into a sheet titled "What
  went wrong?" knowing it is feedback. It ships in the **metadata** tier.
- **`userPrompt` / `assistantReply` are journal-derived.** The user wrote
  their journal for themselves; the reply quotes it back. These ship
  **only** under a separate, per-submission opt-in.

| Tier | Columns | Gate |
|---|---|---|
| `none` | *nothing leaves the device* | **default** |
| `metadata` | rating, category, note, source, zone, model, prompt version, `was_degraded`, safety presentation, app/OS version, citation **count**, timestamps | Settings toggle, off by default |
| `metadata_and_text` | the above **+** `user_prompt`, `assistant_reply` | the toggle **and** a per-submission switch on `ReplyFeedbackSheet` |

Citation entry **IDs** are dropped in favour of a **count**. Spec 041 R5
already forbids citation excerpts; the raw UUIDs are join keys into the
user's private journal and buy nothing analytically.

---

## 2. Database

Migrations live in `supabase/migrations/`, applied with `supabase db push`
against project `ibdtqiembpexzeoyhfim` (already configured in `.mcp.json`).
Everything is in a dedicated `feedback` schema so it never collides with
`public` and can be dropped wholesale.

> The Supabase MCP tools are configured but **not connected in this
> session**, so these are files to apply, not statements already run.

### 2.1 `0001_feedback_schema.sql` — enums and identity

```sql
create schema if not exists feedback;

-- Enums mirror the Swift enums verbatim so a rename fails loudly at ingest.
create type feedback.rating       as enum ('none','positive','negative');
create type feedback.source       as enum ('thumbsUp','thumbsDown','report');
create type feedback.category     as enum ('wrongRecall','madeSomethingUp',
                                           'didntAnswer','tone','safety','other');
create type feedback.event_kind   as enum ('thumbs_up','thumbs_up_undo',
                                           'thumbs_down','thumbs_down_undo','report');
create type feedback.trust_zone   as enum ('z0Device','z1AppleContent',
                                           'z1AppleContentFree','unknown');
create type feedback.consent_tier as enum ('none','metadata','metadata_and_text');
create type feedback.report_status as enum ('new','triaging','resolved','dismissed');

-- One row per install. Anonymous auth user <-> AppStateStore.localUserID.
create table feedback.devices (
  id                 uuid primary key default gen_random_uuid(),
  auth_uid           uuid not null unique references auth.users(id) on delete cascade,
  local_user_id      uuid not null unique,
  platform           text not null default 'ios',
  app_version        text not null default '',
  os_version         text,
  consent_tier       feedback.consent_tier not null default 'none',
  consent_version    text not null default 'v1',
  consent_updated_at timestamptz,
  first_seen_at      timestamptz not null default now(),
  last_seen_at       timestamptz not null default now()
);
```

`local_user_id` is `AppStateStore.localUserID` — a UUID that already exists,
is install-scoped, is **not** an account, and is already destroyed by Delete
Everything (`AppStateStore.swift:227`). Reusing it means this spec invents no
new identifier.

### 2.2 `0002_feedback_tables.sql` — the ledger and the current state

Two tables on purpose. `answer_feedback` mirrors the on-device row 1:1
(thumbs get overwritten, so it answers *"what does this user think of this
answer now?"*). `events` is append-only, so a thumbs-down later undone is
still analyzable — that history is exactly what an eval feed needs and is
destroyed by upsert alone.

```sql
create table feedback.answer_feedback (
  id                  uuid primary key,          -- client AnswerFeedback.id
  device_id           uuid not null references feedback.devices(id) on delete cascade,
  message_id          uuid not null,
  session_id          uuid,
  rating              feedback.rating not null default 'none',
  flagged_for_review  boolean not null default false,
  category            feedback.category,
  note                text check (length(note) <= 1000),
  source              feedback.source not null,
  -- Tier-B only. Null unless text_included.
  user_prompt         text,
  assistant_reply     text,
  text_included       boolean not null default false,
  citation_count      int not null default 0,
  prompt_version      text,
  model_identifier    text,
  zone                feedback.trust_zone not null default 'unknown',
  was_degraded        boolean,
  safety_presentation text not null default 'none',
  app_version         text not null default '',
  client_created_at   timestamptz not null,
  client_updated_at   timestamptz not null,
  received_at         timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint one_row_per_message unique (device_id, message_id),
  -- Structural guarantee: transcript text cannot exist without the flag.
  constraint text_requires_consent check (
    text_included or (user_prompt is null and assistant_reply is null)
  )
);

create table feedback.events (
  id               uuid primary key default gen_random_uuid(),
  device_id        uuid not null references feedback.devices(id) on delete cascade,
  client_event_id  uuid not null,               -- idempotency key
  message_id       uuid not null,
  session_id       uuid,
  kind             feedback.event_kind not null,
  rating_after     feedback.rating,
  category         feedback.category,
  note             text,
  zone             feedback.trust_zone,
  model_identifier text,
  prompt_version   text,
  app_version      text,
  occurred_at      timestamptz not null,        -- client clock
  received_at      timestamptz not null default now(),
  constraint events_idempotent unique (device_id, client_event_id)
);

create table feedback.report_triage (
  feedback_id     uuid primary key references feedback.answer_feedback(id) on delete cascade,
  status          feedback.report_status not null default 'new',
  severity        smallint not null default 3 check (severity between 1 and 4),
  assignee        text,
  resolution_note text,
  opened_at       timestamptz not null default now(),
  resolved_at     timestamptz
);

create index af_device_updated   on feedback.answer_feedback (device_id, updated_at desc);
create index af_flagged          on feedback.answer_feedback (flagged_for_review) where flagged_for_review;
create index af_negative_cat     on feedback.answer_feedback (category) where rating = 'negative';
create index af_model            on feedback.answer_feedback (model_identifier, rating);
create index ev_occurred         on feedback.events (occurred_at desc);
create index ev_kind_occurred    on feedback.events (kind, occurred_at desc);
create index triage_open         on feedback.report_triage (status, severity) where status in ('new','triaging');
```

### 2.3 `0003_feedback_triggers.sql` — "instantly processed"

```sql
create or replace function feedback.touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

create trigger af_touch before update on feedback.answer_feedback
  for each row execute function feedback.touch_updated_at();

-- A report opens a triage row the instant it lands. Safety outranks everything.
create or replace function feedback.open_triage() returns trigger
language plpgsql as $$
begin
  if new.flagged_for_review then
    insert into feedback.report_triage (feedback_id, severity)
    values (new.id, case when new.category = 'safety' then 1 else 3 end)
    on conflict (feedback_id) do update
      set severity = least(feedback.report_triage.severity, excluded.severity);
  end if;
  return new;
end $$;

create trigger af_open_triage after insert or update of flagged_for_review
  on feedback.answer_feedback
  for each row execute function feedback.open_triage();
```

Add a **Database Webhook** on `feedback.report_triage` insert where
`severity = 1` → Slack/email. A safety report should page a human, not wait
for a dashboard refresh.

### 2.4 `0004_feedback_ingest.sql` — the single write path

One `security definer` RPC rather than direct PostgREST table writes. It
buys three things a raw upsert cannot: the event and the current-state row
land in **one transaction**; the consent tier is re-checked **server-side**
so a tampered client cannot smuggle transcript text past a `none` consent;
and idempotency is handled by `client_event_id` so retries are free.

```sql
create or replace function feedback.ingest(payload jsonb)
returns void
language plpgsql
security definer
set search_path = feedback, public
as $$
declare
  v_device  feedback.devices%rowtype;
  v_tier    feedback.consent_tier;
  v_include boolean;
begin
  select * into v_device from feedback.devices where auth_uid = auth.uid();
  if not found then raise exception 'unknown device' using errcode = '42501'; end if;

  v_tier := v_device.consent_tier;
  if v_tier = 'none' then return; end if;           -- silently drop, never store
  v_include := (v_tier = 'metadata_and_text')
               and coalesce((payload->>'text_included')::boolean, false);

  insert into feedback.events (
    device_id, client_event_id, message_id, session_id, kind, rating_after,
    category, note, zone, model_identifier, prompt_version, app_version, occurred_at)
  values (
    v_device.id,
    (payload->>'client_event_id')::uuid,
    (payload->>'message_id')::uuid,
    nullif(payload->>'session_id','')::uuid,
    (payload->>'kind')::feedback.event_kind,
    nullif(payload->>'rating','')::feedback.rating,
    nullif(payload->>'category','')::feedback.category,
    payload->>'note',
    coalesce(nullif(payload->>'zone','')::feedback.trust_zone,'unknown'),
    payload->>'model_identifier',
    payload->>'prompt_version',
    payload->>'app_version',
    (payload->>'occurred_at')::timestamptz)
  on conflict (device_id, client_event_id) do nothing;

  insert into feedback.answer_feedback (
    id, device_id, message_id, session_id, rating, flagged_for_review,
    category, note, source, user_prompt, assistant_reply, text_included,
    citation_count, prompt_version, model_identifier, zone, was_degraded,
    safety_presentation, app_version, client_created_at, client_updated_at)
  values (
    (payload->>'id')::uuid, v_device.id,
    (payload->>'message_id')::uuid,
    nullif(payload->>'session_id','')::uuid,
    coalesce(nullif(payload->>'rating','')::feedback.rating,'none'),
    coalesce((payload->>'flagged_for_review')::boolean,false),
    nullif(payload->>'category','')::feedback.category,
    payload->>'note',
    (payload->>'source')::feedback.source,
    case when v_include then payload->>'user_prompt' end,
    case when v_include then payload->>'assistant_reply' end,
    v_include,
    coalesce((payload->>'citation_count')::int,0),
    payload->>'prompt_version', payload->>'model_identifier',
    coalesce(nullif(payload->>'zone','')::feedback.trust_zone,'unknown'),
    (payload->>'was_degraded')::boolean,
    coalesce(payload->>'safety_presentation','none'),
    coalesce(payload->>'app_version',''),
    (payload->>'client_created_at')::timestamptz,
    (payload->>'client_updated_at')::timestamptz)
  on conflict (device_id, message_id) do update set
    rating             = excluded.rating,
    flagged_for_review = feedback.answer_feedback.flagged_for_review or excluded.flagged_for_review,
    category           = excluded.category,
    note               = excluded.note,
    source             = excluded.source,
    user_prompt        = case when excluded.text_included then excluded.user_prompt
                              else feedback.answer_feedback.user_prompt end,
    assistant_reply    = case when excluded.text_included then excluded.assistant_reply
                              else feedback.answer_feedback.assistant_reply end,
    text_included      = feedback.answer_feedback.text_included or excluded.text_included,
    client_updated_at  = excluded.client_updated_at
    -- Out-of-order retries must not resurrect stale state.
    where excluded.client_updated_at >= feedback.answer_feedback.client_updated_at;

  update feedback.devices
     set last_seen_at = now(),
         app_version  = coalesce(payload->>'app_version', app_version)
   where id = v_device.id;
end $$;

revoke all on function feedback.ingest(jsonb) from public;
grant execute on function feedback.ingest(jsonb) to authenticated;
```

`flagged_for_review` is **monotonic** (`or excluded.…`) — spec 041 R5 says a
report never gets cleared by a later thumbs change, and the SQL enforces it
rather than trusting the client to resend `true`.

### 2.5 `0005_feedback_rls.sql` — write-only client

```sql
alter table feedback.devices        enable row level security;
alter table feedback.answer_feedback enable row level security;
alter table feedback.events          enable row level security;
alter table feedback.report_triage   enable row level security;

-- A device sees and edits only its own registration row.
create policy devices_self on feedback.devices
  for all to authenticated
  using (auth_uid = auth.uid()) with check (auth_uid = auth.uid());

-- Erasure only. All writes go through feedback.ingest (security definer),
-- so there is intentionally NO insert/update/select policy on these tables:
-- the client can never read back a single feedback row, its own included.
create policy af_erase on feedback.answer_feedback
  for delete to authenticated
  using (device_id in (select id from feedback.devices where auth_uid = auth.uid()));

create policy ev_erase on feedback.events
  for delete to authenticated
  using (device_id in (select id from feedback.devices where auth_uid = auth.uid()));
-- report_triage: no client policy at all. Staff read via service_role.
```

Write-only is the point. There is no product feature that needs to read
feedback back — the on-device store already restores the UI (spec 041 R6) —
so granting `select` would create an exfiltration surface for zero benefit.

### 2.6 `0006_feedback_views.sql` — organization

```sql
create view feedback.v_open_reports as
  select t.status, t.severity, t.opened_at, f.category, f.note,
         f.model_identifier, f.prompt_version, f.zone, f.app_version,
         f.text_included, f.id as feedback_id
    from feedback.report_triage t
    join feedback.answer_feedback f on f.id = t.feedback_id
   where t.status in ('new','triaging')
   order by t.severity, t.opened_at;

create view feedback.v_why as            -- the "why" rollup
  select category, count(*) as n,
         count(*) filter (where note is not null and note <> '') as with_note,
         count(*) filter (where flagged_for_review)              as also_reported
    from feedback.answer_feedback
   where rating = 'negative'
   group by category order by n desc;

create view feedback.v_quality_by_model as
  select model_identifier, zone, app_version,
         count(*) filter (where rating = 'positive') as up,
         count(*) filter (where rating = 'negative') as down,
         round(100.0 * count(*) filter (where rating = 'positive')
               / nullif(count(*) filter (where rating <> 'none'),0), 1) as pct_positive
    from feedback.answer_feedback
   group by 1,2,3;

create materialized view feedback.mv_daily as
  select date_trunc('day', occurred_at) as day, kind, count(*) as n
    from feedback.events group by 1,2;
create unique index mv_daily_key on feedback.mv_daily (day, kind);
```

Refresh `mv_daily` concurrently on a `pg_cron` schedule (hourly). The three
plain views are live, so a report is queryable the instant it lands.

### 2.7 `0007_feedback_retention.sql`

```sql
-- Transcript text has the shortest life of anything here.
select cron.schedule('feedback-text-retention','0 4 * * *', $$
  update feedback.answer_feedback
     set user_prompt = null, assistant_reply = null, text_included = false
   where text_included and received_at < now() - interval '90 days';
$$);
```

---

### 2.8 Relationship to spec 043 (added 2026-08-27)

Spec [043](043-eval-run-warehouse.md) builds an `eval` schema plus a warehouse
copy of `answer_feedback` in `public`, on the same project. The two do not
merge, and 043 does not fork this design:

- **This spec stays the landing zone.** `feedback.*` is written by a client
  holding the publishable anon key, through a `security definer` RPC that
  re-derives consent server-side. 043 is service-role/psql only, with
  `anon`/`authenticated` revoked on tables, functions, and schema usage.
- **Opposite retention.** §2.7 purges `user_prompt`/`assistant_reply` after 90
  days. A warehouse whose value is that a six-month-old baseline is still
  comparable cannot share that policy.
- **Different blockers.** This spec is gated behind five compliance guards;
  043 touches no app-target code and no user content, so it ships now.
- **One bridge, one direction.** A `promote_device_feedback()` function reads
  from here into the warehouse with `origin = 'device_human'`. It is written
  only when this spec ships. The warehouse never writes back.

**Two collisions this spec creates, recorded here rather than discovered later:**

1. **`search_path` hazard.** `public.import_answer_feedback` referenced
   `answer_feedback` unqualified with no `set search_path`. The moment
   `feedback.answer_feedback` exists, any caller whose `search_path` starts
   with `feedback` — which §2.4's own functions set — writes to the wrong
   table. 043 closed this by schema-qualifying and pinning `search_path`, but
   the hazard originates here.
2. **Two tables named `answer_feedback`,** distinguished only by schema. That
   is a permanent readability tax on every future query and every future
   session. Renaming this spec's to `feedback.submission` is free while these
   migrations remain unapplied; renaming the warehouse's would mean rewriting
   applied migrations. **Recommend renaming this one.**

---

## 3. Identity: anonymous auth, no accounts

Spec 023 removed account creation; this must not bring it back. Supabase
**anonymous sign-in** issues a JWT with no PII, persisted in the Keychain
alongside the existing `SecurityService` material.

1. First feedback submission (post-consent) → `POST /auth/v1/signup` anonymous
   → store refresh token in Keychain.
2. → `POST /rest/v1/rpc/register_device` with `local_user_id`, platform,
   app/OS version, consent tier (a thin companion RPC that upserts
   `feedback.devices`).
3. Every later submission → `POST /rest/v1/rpc/ingest`.

Turning the Settings toggle **off** deletes the local JWT and issues the
erase in §6 — consent withdrawal is not just a client-side flag flip.

---

## 4. Client architecture

Five new files under `MeetMemento/Services/Feedback/`, all mirroring
patterns the repo already uses:

| File | Role | Models on |
|---|---|---|
| `FeedbackConsent.swift` | tier enum, gate evaluation, redaction | — |
| `FeedbackEnvelope.swift` | wire DTO + `Codable` mapping from `AnswerFeedback` | `AnswerFeedback.swift` |
| `FeedbackOutbox.swift` | durable queue: Application Support JSON, `NSLock` + write-behind, `.completeFileProtection` | `AnswerFeedbackStore.swift` |
| `SupabaseFeedbackClient.swift` | `URLSession` → PostgREST RPC; auth refresh; typed errors | new |
| `FeedbackSyncService.swift` | enqueue → flush → backoff → lifecycle hooks | new |

**No `supabase-swift`.** Three RPC endpoints over `URLSession` is roughly
200 lines and avoids amending the ENFORCING dependency allowlist (blocker
#2), avoids a transitive dependency tree in a near-zero-dependency app, and
keeps the "one third-party network surface" story auditable. Revisit only if
Realtime or Storage is ever needed.

### 4.1 Instant, but durable

"Instantly processed" is a two-part contract:

1. **The local write stays the source of truth and is unchanged.**
   `AnswerFeedbackStore.upsert` still returns synchronously; the UI toast
   fires off the local write. Network latency never blocks a thumb.
2. **The upload starts in the same turn.** `FeedbackSyncService.record(_:)`
   appends to the outbox and kicks an immediate flush. Warm path is a single
   `POST` — typically well under a second — after which the row is live in
   `v_open_reports` / `v_why`, because §2.4 does the event insert, the
   upsert, and the triage trigger in one transaction.

Offline or failing, the outbox retries with exponential backoff (2s → 4s →
… → 5m cap), on `scenePhase == .active`, and on next launch. Entries are
idempotent via `client_event_id`, so a duplicate flush is a no-op server
side. Cap the outbox at 500 entries, dropping oldest, and log the drop.

### 4.2 Where it hooks in

- `ChatViewModel.toggleThumbsUp` / `toggleThumbsDown` / `submitFeedbackDraft`
  / report path → after the existing `AnswerFeedbackStore.upsert`, call
  `FeedbackSyncService.record(row, kind:)`. The **event kind** is derived at
  the call site (only there is undo distinguishable from set), not inferred
  from the row.
- `ChatService.submitFeedback` (`ChatService.swift:623`) keeps its local
  write and gains the same one-line call, so the legacy path is covered.
- `ReplyFeedbackSheet.swift` gains the per-submission "Include the question
  and answer" switch (§1.1), default **off**, shown only when the Settings
  toggle is on.
- `PreferencesService` gains `shareFeedbackWithDeveloper: Bool` (default
  `false`) following the exact `aiEnabled` / `processOnDeviceOnly` pattern
  (`didSet` → `UserDefaults`), and the key joins `resetToDefaults()`.
- `SettingsView` gains the row in the existing "Your Data" section
  (PRES-085), with a reactive subtitle like the other two toggles.

---

## 5. Configuration and secrets

The Supabase **anon key is publishable** — it is designed to ship in
clients, and RLS is what protects the data. It still does not belong in
source (spec 001's secrets audit): put `SUPABASE_URL` and
`SUPABASE_ANON_KEY` in `Config/Supabase.xcconfig` (gitignored, with a
committed `.example`), surfaced through `Info.plist`.

**The `service_role` key must never appear in the app, the repo, or CI for
the app target.** It is for the triage dashboard only.

When the keys are absent, `FeedbackSyncService` compiles and runs as a
no-op — so a fresh clone builds and the local feedback path keeps working
without any backend, exactly as it does today.

---

## 6. Erasure

`AppStateStore.deleteEverything()` (`AppStateStore.swift:201`) already
clears `AnswerFeedbackStore`. It gains a remote leg, following the
`FiveStoreDeletion` precedent of recording an outcome rather than skipping
silently:

```swift
enum FeedbackWipeOutcome: Equatable { case issued, queuedPending, skippedNoConsent }
```

- Issue `DELETE /rest/v1/answer_feedback?device_id=eq.<id>` and the same for
  `events` (the two erase policies in §2.5 are the only client-side table
  grants that exist).
- `on delete cascade` from `answer_feedback` removes the triage rows;
  deleting the `auth.users` row cascades the device registration.
- If offline, persist a **tombstone** and retry on next launch — the local
  UUID is destroyed at line 227, so capture the device id **before** the
  local wipe or the erase becomes unaddressable. This is the single easiest
  bug to ship here.
- Turning the toggle off runs the same path.

---

## 7. Compliance — not optional

### R1. Amend the privacy model (blocker #4)
Spec 014 gains a **`Z2ContentException`** record: a named, spec-owned
exception that, unlike RevenueCat's, *does* carry journal-derived content,
and is therefore bounded by explicit opt-in, tier separation, write-only
RLS, 90-day text retention, and user-initiated erasure. `TrustZone` keeps
its no-`.z2` shape — feedback upload is **not** a `GenerationRequest` and
must not be tagged as one. When spec 014 R4's `NetworkCallSiteAudit` is
built, this call site goes on its allowlist beside RevenueCat, with the
consent gate asserted in the test.

### R2. Privacy manifest (blocker #1)
`PrivacyInfo.xcprivacy` — replace the empty `NSPrivacyCollectedDataTypes`
and its "never transmitted" comment with declared types: **Other User
Content** (Tier B), **Other Data** (feedback metadata), **User ID** (the
anonymous install id). Each: `Linked = true`, `Tracking = false`, purpose
`AppFunctionality` + `Analytics`. Then re-run
`scripts/ci/check_privacy_manifest.sh` — it checks both directions, so the
declaration and the code must agree.

### R3. Store-facing copy (blocker #3)
Update App Store Connect privacy labels; re-amend the published policy at
`meet-memento-ai.github.io/…/privacy.html` **and** `PRIVACY_POLICY.md`;
reopen `docs/app-store/00-readiness-checklist.md` B2 with a dated note. Audit
`docs/app-store/04-metadata-and-assets.md` for on-device claims that this
change falsifies. `REQ-POS-001`'s lint
(`scripts/ci/lint_forbidden_phrases.py`) already bans absolute-privacy
phrasing — verify no *existing* copy now overclaims.

### R4. Spec amendments
- **041** — replace the Out-of-Scope line and the `REQ-PRIV-001` regression
  guard with a dated pointer to this spec.
- **PRES-043** in `frontend-preservation-contract.md` — dated amendment note
  naming spec 042, per that document's own §"Amendments require a dated note
  here plus the deciding spec's ID".
- **022** — `REQ-EVAL-005` says *"all study telemetry is manually collected"*
  and line 329 excludes *"any in-app analytics SDK"*. This is not an SDK, but
  it is automated telemetry: record the narrowing explicitly.
- **README.md / ROADMAP.md** — add 042.

### R5. Dependency allowlist (blocker #2)
Untouched **only because §4 declines the SDK**. If that decision is ever
reversed, `specs/dependency-allowlist.txt` needs a `REQ-MON-005` decision
record before the package may be added, or `spec-gates.yml` fails.

---

## 8. Tasks

- [ ] 1. Write migrations `0001`–`0007`; apply to `ibdtqiembpexzeoyhfim`; verify RLS with an anon JWT (writes succeed, **selects return zero rows**)
- [ ] 2. `FeedbackConsent`, `FeedbackEnvelope`, redaction; `PreferencesService.shareFeedbackWithDeveloper` + `resetToDefaults()`; Settings row
- [ ] 3. `SupabaseFeedbackClient` (anon auth, `register_device`, `ingest`) + xcconfig plumbing + absent-key no-op path
- [ ] 4. `FeedbackOutbox` + `FeedbackSyncService`; wire `ChatViewModel` call sites and `ChatService.submitFeedback`; derive event kinds
- [ ] 5. `ReplyFeedbackSheet` per-submission text switch + copy rewrite (it currently says the report stays on this device — that string becomes false)
- [ ] 6. Erasure leg + tombstone + capture-id-before-wipe; `FeedbackWipeOutcome`
- [ ] 7. §7 compliance: manifest, policy, labels, spec/PRES amendments
- [ ] 8. Tests (§9)

---

## 9. Verification

**Unit / integration**
- Consent `none` → `FeedbackSyncService.record` enqueues nothing and issues no request (assert with a stub `URLProtocol`).
- Consent `metadata` → envelope has `note` and `category`, and `user_prompt`/`assistant_reply` are **nil**.
- Consent `metadata_and_text` **without** the per-submission switch → still nil.
- Outbox survives a process restart; a duplicate flush sends the same `client_event_id` twice and the second is a no-op.
- Delete Everything captures the device id **before** the local wipe, then issues the remote delete; offline leaves a tombstone.
- Report is monotonic: thumbs-up after a report leaves `flagged_for_review = true`.

**Database**
- Insert with a forged `text_included = true` under a `metadata` device → text columns land **null** (§2.4 recomputes server-side).
- Out-of-order upsert (stale `client_updated_at`) does not overwrite newer state.
- Anon JWT `select` on `feedback.answer_feedback` returns **zero rows**, including its own.
- `text_requires_consent` rejects a direct insert of text with the flag false.

**End-to-end**
- Thumbs down → submit reason → row visible in `v_why` within a second; `events` has one `thumbs_down`.
- Report a safety answer → `report_triage` row at `severity = 1` in `v_open_reports` immediately; webhook fires.
- Airplane mode → submit three signals → re-enable → all three land, none duplicated.

**CI**
- `scripts/ci/check_privacy_manifest.sh` passes with the new declarations.
- `scripts/ci/check_dependency_allowlist.sh` still passes (no new package).
- `python3 scripts/ci/lint_forbidden_phrases.py` passes against revised copy.

---

## 10. Out of scope

- In-app review inbox (spec 022 owns the eval harness; §2.6 views + a
  Supabase dashboard are the triage surface)
- LLM-as-judge scoring of reported answers
- Uploading journal entries, reflections, or chat history — **only** the
  feedback row, and its transcript fields only under Tier B
- Realtime subscriptions; Supabase Storage; any read path to the client
- Reinstating a Memento account (spec 023 stands — anonymous auth only)
