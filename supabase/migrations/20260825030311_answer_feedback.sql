-- Spec 041 — In-Chat Answer Feedback: local triage schema.
--
-- This database is LOCAL ONLY. Rows arrive by manual export from a device
-- (AnswerFeedbackStore.exportJSONData) and are loaded by hand. The app does
-- not sync to it and has no networking layer to do so. REQ-PRIV-001 holds:
-- journal-derived content never crosses into Z2.
--
-- Enum values are spelled to match the Swift rawValues exactly, so an
-- exported JSON row imports without a translation layer.

create type answer_feedback_rating as enum (
    'none', 'positive', 'negative'
);

create type answer_feedback_source as enum (
    'thumbsUp', 'thumbsDown', 'report'
);

create type answer_feedback_category as enum (
    'wrongRecall', 'madeSomethingUp', 'didntAnswer', 'tone', 'safety', 'other'
);

create type chat_safety_presentation as enum (
    'none', 'crisisResource', 'hardRefuse', 'emptyObservation'
);

create table answer_feedback (
    -- Identity. message_id is the real key: spec 041 R5 is one row per
    -- assistant message, upserted, so thumbs and Report mutate the same row.
    id                   uuid primary key,
    message_id           uuid not null unique,
    session_id           uuid,

    -- Verdict. Three independent columns, not one status enum: R5 allows a
    -- reply to be negative AND reported, and undoing a thumbs-down must
    -- leave flagged_for_review standing.
    rating               answer_feedback_rating not null default 'none',
    flagged_for_review   boolean not null default false,
    source               answer_feedback_source not null,

    -- Reason. Deliberately NOT constrained to "negative implies category":
    -- ChatService.submitFeedback still writes a negative rating with a null
    -- category on the legacy thumbs path, so a check constraint here would
    -- reject real exported rows. Query for it instead — see the view below.
    category             answer_feedback_category,
    note                 text check (note is null or char_length(note) <= 280),

    -- Reproduction context: enough to replay the failing turn.
    -- citation_entry_ids holds IDs only — never excerpts (REQ-PRIV-001).
    user_prompt          text not null default '',
    assistant_reply      text not null default '',
    citation_entry_ids   uuid[] not null default '{}',

    -- Provenance: what produced the answer, so regressions get a denominator.
    prompt_version       text,
    model_identifier     text,
    zone                 text,
    was_degraded         boolean,
    safety_presentation  chat_safety_presentation not null default 'none',
    app_version          text not null default '',

    created_at           timestamptz not null,
    updated_at           timestamptz not null,

    -- Local-only bookkeeping: when this row landed in the triage DB, which
    -- is not the same as when the user gave the feedback.
    imported_at          timestamptz not null default now()
);

comment on table answer_feedback is
    'Spec 041 quality tickets, imported from device exports. Local triage only.';
comment on column answer_feedback.citation_entry_ids is
    'Journal entry IDs only. Excerpts must never be stored here (REQ-PRIV-001).';

create index answer_feedback_flagged_idx
    on answer_feedback (flagged_for_review, updated_at desc)
    where flagged_for_review;

create index answer_feedback_triage_idx
    on answer_feedback (rating, category, updated_at desc);

create index answer_feedback_provenance_idx
    on answer_feedback (prompt_version, model_identifier);

create index answer_feedback_session_idx
    on answer_feedback (session_id)
    where session_id is not null;

-- Closed by default. No policies are defined, so PostgREST (anon/authenticated)
-- can read nothing; local psql/service-role access is unaffected. Costs nothing
-- locally and means an accidental exposure fails shut rather than open.
alter table answer_feedback enable row level security;

-- Triage queue: what actually needs looking at, worst first.
create view answer_feedback_queue as
select
    message_id,
    rating,
    flagged_for_review,
    category,
    note,
    user_prompt,
    assistant_reply,
    prompt_version,
    model_identifier,
    was_degraded,
    safety_presentation,
    -- coalesce, because array_length returns NULL (not 0) on an empty array,
    -- which would make the "no citations" case invisible to the query below.
    coalesce(array_length(citation_entry_ids, 1), 0) as citation_count,
    updated_at
from answer_feedback
where rating = 'negative' or flagged_for_review
order by flagged_for_review desc, updated_at desc;

comment on view answer_feedback_queue is
    'Negative or reported replies. citation_count = 0 on a wrongRecall row '
    'points at retrieval rather than generation.';
