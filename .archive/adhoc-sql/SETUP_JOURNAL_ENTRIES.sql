-- ================================================
-- JOURNAL ENTRIES TABLE & TRACKING SETUP
-- ================================================
-- Creates/updates the entries table for storing journal content
-- Adds functions to track entry counts per user
--
-- INSTRUCTIONS:
-- 1. Open Supabase Dashboard → SQL Editor
-- 2. Copy-paste this ENTIRE block
-- 3. Click "Run"
-- 4. Done! Journal entries and counting will work.
--
-- INTEGRATES WITH EXISTING CODE ✅
-- ================================================

-- ================================================
-- 1. CREATE OR UPDATE ENTRIES TABLE
-- ================================================

-- Create entries table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT,
  text TEXT NOT NULL,  -- Journal content (string)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_entries_user_id ON public.entries(user_id);
CREATE INDEX IF NOT EXISTS idx_entries_created_at ON public.entries(created_at DESC);

-- Add comment
COMMENT ON TABLE public.entries IS 'Stores journal entries for each user';
COMMENT ON COLUMN public.entries.text IS 'Journal entry content (string)';
COMMENT ON COLUMN public.entries.user_id IS 'User who owns this entry';

-- ================================================
-- 2. ROW LEVEL SECURITY (RLS)
-- ================================================

-- Enable RLS on entries table
ALTER TABLE public.entries ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own entries
DROP POLICY IF EXISTS "Users can view their own entries" ON public.entries;
CREATE POLICY "Users can view their own entries"
  ON public.entries
  FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: Users can only insert their own entries
DROP POLICY IF EXISTS "Users can create their own entries" ON public.entries;
CREATE POLICY "Users can create their own entries"
  ON public.entries
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: Users can only update their own entries
DROP POLICY IF EXISTS "Users can update their own entries" ON public.entries;
CREATE POLICY "Users can update their own entries"
  ON public.entries
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Policy: Users can only delete their own entries
DROP POLICY IF EXISTS "Users can delete their own entries" ON public.entries;
CREATE POLICY "Users can delete their own entries"
  ON public.entries
  FOR DELETE
  USING (auth.uid() = user_id);

-- ================================================
-- 3. FUNCTION: GET ENTRY COUNT FOR CURRENT USER
-- ================================================

-- Function to get the total number of entries for current user
DROP FUNCTION IF EXISTS get_user_entry_count();

CREATE OR REPLACE FUNCTION get_user_entry_count()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
  entry_count integer;
BEGIN
  -- Get current authenticated user
  current_user_id := auth.uid();

  -- Check authentication
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Count entries for this user
  SELECT COUNT(*)::integer INTO entry_count
  FROM public.entries
  WHERE user_id = current_user_id;

  RETURN entry_count;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_user_entry_count() TO authenticated;

COMMENT ON FUNCTION get_user_entry_count() IS
'Returns the total number of journal entries for the current authenticated user';

-- ================================================
-- 4. FUNCTION: GET ENTRY STATS FOR CURRENT USER
-- ================================================

-- Function to get detailed entry statistics
DROP FUNCTION IF EXISTS get_user_entry_stats();

CREATE OR REPLACE FUNCTION get_user_entry_stats()
RETURNS TABLE (
  total_entries INTEGER,
  entries_this_week INTEGER,
  entries_this_month INTEGER,
  first_entry_date TIMESTAMPTZ,
  last_entry_date TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  -- Get current authenticated user
  current_user_id := auth.uid();

  -- Check authentication
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Return statistics
  RETURN QUERY
  SELECT
    COUNT(*)::integer AS total_entries,
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::integer AS entries_this_week,
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')::integer AS entries_this_month,
    MIN(created_at) AS first_entry_date,
    MAX(created_at) AS last_entry_date
  FROM public.entries
  WHERE user_id = current_user_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_user_entry_stats() TO authenticated;

COMMENT ON FUNCTION get_user_entry_stats() IS
'Returns detailed statistics about journal entries for the current authenticated user';

-- ================================================
-- 5. TRIGGER: AUTO-UPDATE updated_at TIMESTAMP
-- ================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists
DROP TRIGGER IF EXISTS update_entries_updated_at ON public.entries;

-- Create trigger
CREATE TRIGGER update_entries_updated_at
  BEFORE UPDATE ON public.entries
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TRIGGER update_entries_updated_at ON public.entries IS
'Automatically updates the updated_at timestamp when an entry is modified';

-- ================================================
-- 6. VERIFICATION QUERIES (Optional - Run separately)
-- ================================================

-- Uncomment these to verify setup:
--
-- -- Check if table exists
-- SELECT table_name, table_type
-- FROM information_schema.tables
-- WHERE table_schema = 'public'
-- AND table_name = 'entries';
--
-- -- Check RLS policies
-- SELECT schemaname, tablename, policyname, cmd
-- FROM pg_policies
-- WHERE tablename = 'entries';
--
-- -- Check functions
-- SELECT routine_name, routine_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
-- AND routine_name IN ('get_user_entry_count', 'get_user_entry_stats');
--
-- ================================================
-- SETUP COMPLETE! ✅
-- ================================================
-- Your app can now:
-- 1. ✅ Store journal entries (text string)
-- 2. ✅ Track entry count (integer)
-- 3. ✅ Get detailed statistics
-- 4. ✅ Auto-update timestamps
-- 5. ✅ Secure with Row Level Security
-- ================================================
