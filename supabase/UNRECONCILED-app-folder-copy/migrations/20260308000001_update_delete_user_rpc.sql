-- Migration: Update delete_user() RPC to handle all tables
-- Date: 2026-03-08

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
    -- Step 1: Delete app data (explicit, for safety even though CASCADE exists)
    DELETE FROM public.journal_entries WHERE user_id = current_user_id;
    DELETE FROM public.chat_messages WHERE user_id = current_user_id;
    DELETE FROM public.chat_sessions WHERE user_id = current_user_id;
    DELETE FROM public.users WHERE id = current_user_id;

    -- Step 2: Delete from auth.users (triggers CASCADE as backup)
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
