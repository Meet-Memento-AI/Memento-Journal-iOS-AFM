-- Close the PostgREST path to answer_feedback (spec 041, REQ-PRIV-001).
--
-- Enabling RLS on the base table is not sufficient on its own:
--
--   1. A Postgres view executes with its OWNER's privileges unless it is
--      declared security_invoker. answer_feedback_queue is owned by
--      "postgres", which also owns answer_feedback, and a table owner is
--      exempt from RLS on its own table. So the view read straight through
--      the base table's RLS and returned every row.
--
--   2. Supabase's default privileges (ALTER DEFAULT PRIVILEGES ... GRANT ALL
--      ON TABLES TO "anon") apply automatically to anything created in
--      public, so both the table and the view were granted to "anon" — a key
--      that is public by design and ships in client code.
--
-- Together those two meant the anon key could read user_prompt and
-- assistant_reply through the view. Fixed on both axes below.

-- 1. Make the view respect the caller's RLS rather than the owner's.
alter view public.answer_feedback_queue set (security_invoker = on);

-- 2. Revoke the inherited default grants. This database is reached by
--    psql/service_role for triage, never by an anon client, so anon and
--    authenticated have no business here at all.
revoke all on table public.answer_feedback from anon, authenticated;
revoke all on table public.answer_feedback_queue from anon, authenticated;
revoke all on function public.import_answer_feedback(jsonb) from anon, authenticated;

-- 3. Stop the same default grants from re-applying to future objects here.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
