-- ============================================================
-- Migration: Add User Statistics Table
-- Date: 2025-10-23
-- Purpose: Pre-computed statistics to avoid expensive COUNT() queries
-- ============================================================

-- ============================================================
-- 1. CREATE USER_STATS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS user_stats (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Entry counts
  total_entries int NOT NULL DEFAULT 0,
  total_words int NOT NULL DEFAULT 0,

  -- Streaks
  current_streak int NOT NULL DEFAULT 0,       -- Consecutive days with entries
  longest_streak int NOT NULL DEFAULT 0,       -- Best ever streak
  last_streak_check_date date,                 -- Last date streak was calculated

  -- Activity timestamps
  first_entry_date timestamptz,                -- Date of first ever entry
  last_entry_date timestamptz,                 -- Date of most recent entry

  -- Writing pace (entries per week over different periods)
  entries_this_week int NOT NULL DEFAULT 0,
  entries_this_month int NOT NULL DEFAULT 0,
  entries_this_year int NOT NULL DEFAULT 0,

  -- Average metrics
  avg_words_per_entry int NOT NULL DEFAULT 0,
  avg_entries_per_week decimal(5,2) NOT NULL DEFAULT 0,

  -- Timestamps
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_recalculated_at timestamptz             -- When stats were last fully recalculated
);

-- ============================================================
-- 2. ADD INDEXES
-- ============================================================

-- Index for finding active users
CREATE INDEX IF NOT EXISTS idx_user_stats_last_entry
  ON user_stats(last_entry_date DESC)
  WHERE last_entry_date IS NOT NULL;

-- Index for streak leaderboards (optional future feature)
CREATE INDEX IF NOT EXISTS idx_user_stats_longest_streak
  ON user_stats(longest_streak DESC)
  WHERE longest_streak > 0;

-- Index for finding users who need stats updates
CREATE INDEX IF NOT EXISTS idx_user_stats_needs_update
  ON user_stats(last_recalculated_at NULLS FIRST);

-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE user_stats ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own stats" ON user_stats;
DROP POLICY IF EXISTS "Users can insert own stats" ON user_stats;
DROP POLICY IF EXISTS "Users can update own stats" ON user_stats;

-- Users can only access their own stats
CREATE POLICY "Users can view own stats"
  ON user_stats FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own stats"
  ON user_stats FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own stats"
  ON user_stats FOR UPDATE
  USING (auth.uid() = user_id);

-- ============================================================
-- 4. ADD CONSTRAINTS
-- ============================================================

-- All counts must be non-negative
ALTER TABLE user_stats
  DROP CONSTRAINT IF EXISTS counts_non_negative;

ALTER TABLE user_stats
  ADD CONSTRAINT counts_non_negative
    CHECK (
      total_entries >= 0 AND
      total_words >= 0 AND
      current_streak >= 0 AND
      longest_streak >= 0 AND
      entries_this_week >= 0 AND
      entries_this_month >= 0 AND
      entries_this_year >= 0 AND
      avg_words_per_entry >= 0
    );

-- Current streak cannot exceed longest streak
ALTER TABLE user_stats
  DROP CONSTRAINT IF EXISTS current_streak_valid;

ALTER TABLE user_stats
  ADD CONSTRAINT current_streak_valid
    CHECK (current_streak <= longest_streak);

-- Last entry date must be after first entry date
ALTER TABLE user_stats
  DROP CONSTRAINT IF EXISTS entry_dates_valid;

ALTER TABLE user_stats
  ADD CONSTRAINT entry_dates_valid
    CHECK (
      (first_entry_date IS NULL AND last_entry_date IS NULL) OR
      (first_entry_date IS NOT NULL AND last_entry_date IS NOT NULL AND last_entry_date >= first_entry_date)
    );

-- ============================================================
-- 5. UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_user_stats_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_stats_updated_at ON user_stats;
CREATE TRIGGER trigger_update_user_stats_updated_at
  BEFORE UPDATE ON user_stats
  FOR EACH ROW
  EXECUTE FUNCTION update_user_stats_updated_at();

-- ============================================================
-- 6. AUTO-UPDATE STATS ON ENTRY CHANGES
-- ============================================================

CREATE OR REPLACE FUNCTION update_user_stats_on_entry_change()
RETURNS TRIGGER AS $$
DECLARE
  word_count int;
  user_uuid uuid;
BEGIN
  -- Determine which user to update
  user_uuid := COALESCE(NEW.user_id, OLD.user_id);

  -- Ensure user has a stats row
  INSERT INTO user_stats (user_id)
  VALUES (user_uuid)
  ON CONFLICT (user_id) DO NOTHING;

  -- Calculate word count for new/updated entries
  IF NEW IS NOT NULL THEN
    word_count := array_length(regexp_split_to_array(NEW.text, '\s+'), 1);
  END IF;

  -- Handle INSERT
  IF TG_OP = 'INSERT' THEN
    UPDATE user_stats
    SET
      total_entries = total_entries + 1,
      total_words = total_words + word_count,
      last_entry_date = GREATEST(COALESCE(last_entry_date, NEW.created_at), NEW.created_at),
      first_entry_date = LEAST(COALESCE(first_entry_date, NEW.created_at), NEW.created_at),
      avg_words_per_entry = CASE
        WHEN total_entries + 1 > 0 THEN (total_words + word_count) / (total_entries + 1)
        ELSE 0
      END
    WHERE user_id = user_uuid;

  -- Handle UPDATE
  ELSIF TG_OP = 'UPDATE' THEN
    -- Recalculate if text changed
    IF OLD.text <> NEW.text THEN
      DECLARE
        old_word_count int;
      BEGIN
        old_word_count := array_length(regexp_split_to_array(OLD.text, '\s+'), 1);

        UPDATE user_stats
        SET
          total_words = total_words - old_word_count + word_count,
          avg_words_per_entry = CASE
            WHEN total_entries > 0 THEN (total_words - old_word_count + word_count) / total_entries
            ELSE 0
          END
        WHERE user_id = user_uuid;
      END;
    END IF;

  -- Handle DELETE
  ELSIF TG_OP = 'DELETE' THEN
    DECLARE
      old_word_count int;
    BEGIN
      old_word_count := array_length(regexp_split_to_array(OLD.text, '\s+'), 1);

      UPDATE user_stats
      SET
        total_entries = GREATEST(total_entries - 1, 0),
        total_words = GREATEST(total_words - old_word_count, 0),
        avg_words_per_entry = CASE
          WHEN total_entries - 1 > 0 THEN (total_words - old_word_count) / (total_entries - 1)
          ELSE 0
        END
      WHERE user_id = user_uuid;

      -- Update last_entry_date if we deleted the most recent entry
      UPDATE user_stats us
      SET
        last_entry_date = (SELECT MAX(created_at) FROM entries e WHERE e.user_id = us.user_id),
        first_entry_date = (SELECT MIN(created_at) FROM entries e WHERE e.user_id = us.user_id)
      WHERE us.user_id = user_uuid;
    END;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_stats_on_entry_insert ON entries;
CREATE TRIGGER trigger_update_stats_on_entry_insert
  AFTER INSERT ON entries
  FOR EACH ROW
  EXECUTE FUNCTION update_user_stats_on_entry_change();

DROP TRIGGER IF EXISTS trigger_update_stats_on_entry_update ON entries;
CREATE TRIGGER trigger_update_stats_on_entry_update
  AFTER UPDATE ON entries
  FOR EACH ROW
  WHEN (OLD.text IS DISTINCT FROM NEW.text)
  EXECUTE FUNCTION update_user_stats_on_entry_change();

DROP TRIGGER IF EXISTS trigger_update_stats_on_entry_delete ON entries;
CREATE TRIGGER trigger_update_stats_on_entry_delete
  AFTER DELETE ON entries
  FOR EACH ROW
  EXECUTE FUNCTION update_user_stats_on_entry_change();

-- ============================================================
-- 7. HELPER FUNCTIONS
-- ============================================================

-- Function to fully recalculate stats for a user
CREATE OR REPLACE FUNCTION recalculate_user_stats(p_user_id uuid)
RETURNS void AS $$
DECLARE
  stats_record RECORD;
BEGIN
  -- Calculate all stats from entries
  SELECT
    COUNT(*) as total,
    SUM(array_length(regexp_split_to_array(text, '\s+'), 1)) as words,
    MIN(created_at) as first_date,
    MAX(created_at) as last_date,
    CASE
      WHEN COUNT(*) > 0 THEN
        SUM(array_length(regexp_split_to_array(text, '\s+'), 1)) / COUNT(*)
      ELSE 0
    END as avg_words
  INTO stats_record
  FROM entries
  WHERE user_id = p_user_id;

  -- Upsert stats
  INSERT INTO user_stats (
    user_id,
    total_entries,
    total_words,
    first_entry_date,
    last_entry_date,
    avg_words_per_entry,
    last_recalculated_at
  ) VALUES (
    p_user_id,
    COALESCE(stats_record.total, 0),
    COALESCE(stats_record.words, 0),
    stats_record.first_date,
    stats_record.last_date,
    COALESCE(stats_record.avg_words, 0),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    total_entries = COALESCE(stats_record.total, 0),
    total_words = COALESCE(stats_record.words, 0),
    first_entry_date = stats_record.first_date,
    last_entry_date = stats_record.last_date,
    avg_words_per_entry = COALESCE(stats_record.avg_words, 0),
    last_recalculated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to calculate writing streaks
CREATE OR REPLACE FUNCTION calculate_writing_streak(p_user_id uuid)
RETURNS TABLE (
  current_streak int,
  longest_streak int
) AS $$
DECLARE
  current int := 0;
  longest int := 0;
  prev_date date := NULL;
  entry_date date;
BEGIN
  -- Loop through all entry dates in chronological order
  FOR entry_date IN
    SELECT DISTINCT date(created_at) as entry_date
    FROM entries
    WHERE user_id = p_user_id
    ORDER BY entry_date ASC
  LOOP
    -- Check if this continues the streak
    IF prev_date IS NULL OR entry_date = prev_date + 1 THEN
      current := current + 1;
      longest := GREATEST(longest, current);
    ELSE
      current := 1; -- Reset streak
    END IF;

    prev_date := entry_date;
  END LOOP;

  -- Check if current streak is still active (entry today or yesterday)
  IF prev_date IS NOT NULL AND prev_date < CURRENT_DATE - 1 THEN
    current := 0; -- Streak is broken
  END IF;

  RETURN QUERY SELECT current, longest;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update period counts (week/month/year)
CREATE OR REPLACE FUNCTION update_period_counts(p_user_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE user_stats
  SET
    entries_this_week = (
      SELECT COUNT(*)
      FROM entries
      WHERE user_id = p_user_id
        AND created_at >= date_trunc('week', now())
    ),
    entries_this_month = (
      SELECT COUNT(*)
      FROM entries
      WHERE user_id = p_user_id
        AND created_at >= date_trunc('month', now())
    ),
    entries_this_year = (
      SELECT COUNT(*)
      FROM entries
      WHERE user_id = p_user_id
        AND created_at >= date_trunc('year', now())
    )
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 8. INITIALIZE STATS FOR EXISTING USERS
-- ============================================================

-- Create stats rows for all existing users when the existing schema still
-- references auth.users. Older production schemas may point elsewhere.
DO $$
DECLARE
  fk_targets_auth_users boolean;
  user_record RECORD;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint constraint_def
    JOIN pg_class table_def ON table_def.oid = constraint_def.conrelid
    JOIN pg_namespace table_ns ON table_ns.oid = table_def.relnamespace
    JOIN pg_attribute column_def
      ON column_def.attrelid = table_def.oid
      AND column_def.attnum = ANY (constraint_def.conkey)
    JOIN pg_class referenced_table ON referenced_table.oid = constraint_def.confrelid
    JOIN pg_namespace referenced_ns ON referenced_ns.oid = referenced_table.relnamespace
    WHERE constraint_def.contype = 'f'
      AND table_ns.nspname = 'public'
      AND table_def.relname = 'user_stats'
      AND column_def.attname = 'user_id'
      AND referenced_ns.nspname = 'auth'
      AND referenced_table.relname = 'users'
  ) INTO fk_targets_auth_users;

  IF fk_targets_auth_users THEN
    INSERT INTO user_stats (user_id)
    SELECT auth_user.id
    FROM auth.users AS auth_user
    ON CONFLICT (user_id) DO NOTHING;
  ELSE
    RAISE NOTICE 'Skipping user_stats auth.users backfill because existing foreign key target is not auth.users';
  END IF;

-- Recalculate stats for all users with entries
  FOR user_record IN
    SELECT DISTINCT user_id
    FROM entries
  LOOP
    PERFORM recalculate_user_stats(user_record.user_id);
  END LOOP;

  RAISE NOTICE '✅ Initialized stats for existing users';
END $$;

-- ============================================================
-- 9. ADD HELPFUL COMMENTS
-- ============================================================
  FOR user_record IN
    SELECT DISTINCT user_id
    FROM entries
  LOOP
    PERFORM recalculate_user_stats(user_record.user_id);
  END LOOP;

  RAISE NOTICE '✅ Initialized stats for existing users';
END $$;

-- ============================================================
-- 9. ADD HELPFUL COMMENTS
-- ============================================================

COMMENT ON TABLE user_stats IS 'Pre-computed user statistics to avoid expensive queries';
COMMENT ON COLUMN user_stats.total_entries IS 'Total number of journal entries (updated via triggers)';
COMMENT ON COLUMN user_stats.total_words IS 'Total words across all entries (updated via triggers)';
COMMENT ON COLUMN user_stats.current_streak IS 'Consecutive days with at least one entry';
COMMENT ON COLUMN user_stats.longest_streak IS 'Best ever writing streak';
COMMENT ON COLUMN user_stats.avg_words_per_entry IS 'Average words per entry (automatically maintained)';

-- ============================================================
-- 10. VALIDATION
-- ============================================================

DO $$
DECLARE
  stats_count INTEGER;
  users_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO stats_count FROM user_stats;
  SELECT COUNT(*) INTO users_count FROM auth.users;

  RAISE NOTICE '✅ User statistics table created successfully';
  RAISE NOTICE '   - Stats rows created: %', stats_count;
  RAISE NOTICE '   - Total auth users: %', users_count;
  RAISE NOTICE '   - Auto-update triggers: 3 (on INSERT, UPDATE, DELETE)';
  RAISE NOTICE '   - Helper functions: recalculate_user_stats, calculate_writing_streak, update_period_counts';
END $$;
