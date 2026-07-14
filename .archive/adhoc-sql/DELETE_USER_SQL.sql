-- ================================================
-- DELETE USER FUNCTION FOR MEETMEMENTO
-- ================================================
-- This SQL creates a function to delete users via the
-- "Delete Account" button in SettingsView.swift
--
-- INSTRUCTIONS:
-- 1. Open Supabase Dashboard → SQL Editor
-- 2. Copy-paste this ENTIRE file
-- 3. Click "Run"
-- 4. When warning appears: Click "I understand" or "Continue"
-- 5. Done! Your delete button will now work.
--
-- NO APP CODE CHANGES NEEDED ✅
-- ================================================

-- Clean up: Remove old function if exists
DROP FUNCTION IF EXISTS delete_user();

-- Create the delete_user function
-- This is called by SupabaseService.swift line 451:
-- try await client.rpc("delete_user").execute()
CREATE OR REPLACE FUNCTION delete_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  -- SAFETY: Get only the authenticated user's ID
  current_user_id := auth.uid();

  -- SAFETY: Verify user is authenticated
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated. Cannot delete account.';
  END IF;

  -- Transaction: All-or-nothing deletion
  BEGIN
    -- Step 1: Delete all journal entries for this user
    DELETE FROM public.entries WHERE user_id = current_user_id;

    -- Step 2: Delete the user from auth.users
    -- This also deletes user_metadata automatically
    DELETE FROM auth.users WHERE id = current_user_id;

    -- Log success
    RAISE NOTICE 'User % deleted successfully', current_user_id;

  EXCEPTION
    WHEN OTHERS THEN
      -- Transaction auto-rolls back on error
      RAISE EXCEPTION 'Failed to delete user: %', SQLERRM;
  END;
END;
$$;

-- SECURITY: Grant execute permission to authenticated users ONLY
GRANT EXECUTE ON FUNCTION delete_user() TO authenticated;

-- SECURITY: Revoke from everyone else
REVOKE EXECUTE ON FUNCTION delete_user() FROM anon;
REVOKE EXECUTE ON FUNCTION delete_user() FROM public;

-- Documentation
COMMENT ON FUNCTION delete_user() IS
'Deletes the currently authenticated user and all their data.
Called by MeetMemento app via SupabaseService.deleteAccount().
Can only be executed by authenticated users on their own account.';

-- ================================================
-- VERIFICATION QUERY (Optional)
-- ================================================
-- Run this after to verify function was created:
--
-- SELECT routine_name, routine_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
-- AND routine_name = 'delete_user';
--
-- Should return:
-- routine_name | routine_type
-- delete_user  | FUNCTION
-- ================================================
