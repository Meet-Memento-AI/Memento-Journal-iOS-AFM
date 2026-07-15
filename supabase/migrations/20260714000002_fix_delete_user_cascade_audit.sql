-- Migration: delete_user() cascade-complete rewrite (spec-003 R3/R4).
--
-- The prior version (20260308000001) explicitly deleted only journal_entries,
-- chat_messages, chat_sessions, then public.users, before deleting auth.users.
-- public.users didn't exist in the canonical chain until this spec (see
-- 20260304000001), so this RPC threw and rolled back on every fresh replay.
--
-- Cascade audit (spec-003 R4) — every user-owned table and how it's cleared:
--
-- | Table              | Cleared by                                  |
-- |--------------------|----------------------------------------------|
-- | chat_feedback      | explicit DELETE here + FK CASCADE (user_id,   |
-- |                    | and message_id -> chat_messages)              |
-- | chat_messages      | explicit DELETE here + FK CASCADE (user_id)   |
-- | chat_sessions      | explicit DELETE here + FK CASCADE (user_id)   |
-- | journal_entries    | explicit DELETE here + FK CASCADE (user_id)   |
-- | user_chat_caches   | explicit DELETE here + FK CASCADE (user_id)   |
-- | user_insights      | explicit DELETE here + FK CASCADE (user_id)   |
-- | user_stats         | explicit DELETE here + FK CASCADE (user_id PK)|
-- | user_profiles      | explicit DELETE here + FK CASCADE (user_id PK)|
-- | rate_limits        | explicit DELETE here + FK CASCADE (user_id)   |
-- | ai_feedback        | explicit DELETE here + FK CASCADE (user_id)   |
-- | public.users       | explicit DELETE here + FK CASCADE (id PK)     |
-- | themes             | global reference data, not user-owned         |
-- | subscription_plans | global reference data, not user-owned         |
--
-- Every one of the above already has `ON DELETE CASCADE` to auth.users(id), so
-- the explicit deletes are defense-in-depth (matching the "explicit, for safety
-- even though CASCADE exists" approach the original author chose) rather than
-- the only thing standing between deletion and orphaned rows. Deleting
-- auth.users last is what actually guarantees completeness even if a future
-- table is added without updating this function.

CREATE OR REPLACE FUNCTION delete_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  current_user_id := auth.uid();

  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated. Cannot delete account.';
  END IF;

  BEGIN
    DELETE FROM public.chat_feedback WHERE user_id = current_user_id;
    DELETE FROM public.chat_messages WHERE user_id = current_user_id;
    DELETE FROM public.chat_sessions WHERE user_id = current_user_id;
    DELETE FROM public.journal_entries WHERE user_id = current_user_id;
    DELETE FROM public.user_chat_caches WHERE user_id = current_user_id;
    DELETE FROM public.user_insights WHERE user_id = current_user_id;
    DELETE FROM public.user_stats WHERE user_id = current_user_id;
    DELETE FROM public.user_profiles WHERE user_id = current_user_id;
    DELETE FROM public.rate_limits WHERE user_id = current_user_id;
    DELETE FROM public.ai_feedback WHERE user_id = current_user_id;
    DELETE FROM public.users WHERE id = current_user_id;

    -- Backstop: catches anything above missed and anything future tables add,
    -- as long as their FK is ON DELETE CASCADE.
    DELETE FROM auth.users WHERE id = current_user_id;

    RAISE NOTICE 'User % deleted successfully', current_user_id;

  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Failed to delete user: %', SQLERRM;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_user() TO authenticated;
REVOKE EXECUTE ON FUNCTION delete_user() FROM anon;
REVOKE EXECUTE ON FUNCTION delete_user() FROM public;
