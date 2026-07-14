-- ============================================================
-- Migration: Add Insights Cache Table
-- Date: 2025-10-23
-- Purpose: Cache expensive AI-generated insights to reduce API calls
-- ============================================================

-- ============================================================
-- 1. CREATE USER_INSIGHTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS user_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Insight metadata
  insight_type text NOT NULL,  -- 'theme_summary', 'monthly_insights', 'weekly_recap', etc.
  content jsonb NOT NULL,      -- Flexible JSON structure for different insight types

  -- Cache invalidation tracking
  entries_analyzed_count int NOT NULL DEFAULT 0,  -- Number of entries used for this insight
  entries_snapshot jsonb,                         -- Optional: store entry IDs for precise invalidation
  date_range_start timestamptz,                   -- Optional: for time-based insights
  date_range_end timestamptz,                     -- Optional: for time-based insights

  -- Cache expiry
  generated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,                         -- Optional: TTL for automatic expiry
  is_valid boolean NOT NULL DEFAULT true,         -- Manual invalidation flag

  -- Metadata
  generation_time_ms int,                         -- Track how long AI took to generate
  model_version text,                             -- Track which AI model/version used
  prompt_tokens int,                              -- Track API usage
  completion_tokens int,                          -- Track API usage

  -- Timestamps
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. ADD INDEXES
-- ============================================================

-- Index for fetching user's insights
CREATE INDEX IF NOT EXISTS idx_user_insights_user_id
  ON user_insights(user_id);

-- Index for fetching specific insight type
CREATE INDEX IF NOT EXISTS idx_user_insights_type
  ON user_insights(user_id, insight_type, is_valid)
  WHERE is_valid = true;

-- Index for cache expiry cleanup
CREATE INDEX IF NOT EXISTS idx_user_insights_expires
  ON user_insights(expires_at)
  WHERE expires_at IS NOT NULL AND is_valid = true;

-- Index for date range queries
CREATE INDEX IF NOT EXISTS idx_user_insights_date_range
  ON user_insights(user_id, date_range_start, date_range_end)
  WHERE date_range_start IS NOT NULL;

-- GIN index for JSONB content searches (optional, for future features)
CREATE INDEX IF NOT EXISTS idx_user_insights_content_gin
  ON user_insights USING gin(content);

-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE user_insights ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own insights" ON user_insights;
DROP POLICY IF EXISTS "Users can insert own insights" ON user_insights;
DROP POLICY IF EXISTS "Users can update own insights" ON user_insights;
DROP POLICY IF EXISTS "Users can delete own insights" ON user_insights;

-- Users can only access their own insights
CREATE POLICY "Users can view own insights"
  ON user_insights FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own insights"
  ON user_insights FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own insights"
  ON user_insights FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own insights"
  ON user_insights FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 4. ADD CONSTRAINTS
-- ============================================================

-- Insight type must be valid
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS insight_type_valid;

ALTER TABLE user_insights
  ADD CONSTRAINT insight_type_valid
    CHECK (insight_type IN (
      'theme_summary',
      'monthly_insights',
      'weekly_recap',
      'annual_review',
      'custom_query'
    ));

-- Content must not be empty
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS content_not_empty;

ALTER TABLE user_insights
  ADD CONSTRAINT content_not_empty
    CHECK (jsonb_typeof(content) = 'object' AND content != '{}'::jsonb);

-- Entries analyzed count must be non-negative
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS entries_count_positive;

ALTER TABLE user_insights
  ADD CONSTRAINT entries_count_positive
    CHECK (entries_analyzed_count >= 0);

-- Date range validation
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS date_range_valid;

ALTER TABLE user_insights
  ADD CONSTRAINT date_range_valid
    CHECK (
      (date_range_start IS NULL AND date_range_end IS NULL) OR
      (date_range_start IS NOT NULL AND date_range_end IS NOT NULL AND date_range_end >= date_range_start)
    );

-- Expires_at must be in the future
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS expires_future;

ALTER TABLE user_insights
  ADD CONSTRAINT expires_future
    CHECK (expires_at IS NULL OR expires_at > created_at);

-- ============================================================
-- 5. UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_user_insights_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_insights_updated_at ON user_insights;
CREATE TRIGGER trigger_update_user_insights_updated_at
  BEFORE UPDATE ON user_insights
  FOR EACH ROW
  EXECUTE FUNCTION update_user_insights_updated_at();

-- ============================================================
-- 6. AUTO-INVALIDATION TRIGGER (when user creates/updates/deletes entries)
-- ============================================================

CREATE OR REPLACE FUNCTION invalidate_user_insights_on_entry_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Invalidate all insights for this user when entries change
  UPDATE user_insights
  SET is_valid = false
  WHERE user_id = COALESCE(NEW.user_id, OLD.user_id)
    AND is_valid = true;

  -- For time-based insights, only invalidate relevant date ranges
  UPDATE user_insights
  SET is_valid = false
  WHERE user_id = COALESCE(NEW.user_id, OLD.user_id)
    AND is_valid = true
    AND date_range_start IS NOT NULL
    AND date_range_end IS NOT NULL
    AND COALESCE(NEW.created_at, OLD.created_at) BETWEEN date_range_start AND date_range_end;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_invalidate_insights_on_entry_insert ON entries;
CREATE TRIGGER trigger_invalidate_insights_on_entry_insert
  AFTER INSERT ON entries
  FOR EACH ROW
  EXECUTE FUNCTION invalidate_user_insights_on_entry_change();

DROP TRIGGER IF EXISTS trigger_invalidate_insights_on_entry_update ON entries;
CREATE TRIGGER trigger_invalidate_insights_on_entry_update
  AFTER UPDATE ON entries
  FOR EACH ROW
  EXECUTE FUNCTION invalidate_user_insights_on_entry_change();

DROP TRIGGER IF EXISTS trigger_invalidate_insights_on_entry_delete ON entries;
CREATE TRIGGER trigger_invalidate_insights_on_entry_delete
  AFTER DELETE ON entries
  FOR EACH ROW
  EXECUTE FUNCTION invalidate_user_insights_on_entry_change();

-- ============================================================
-- 7. HELPER FUNCTIONS
-- ============================================================

-- Function to get valid cached insight
DROP FUNCTION IF EXISTS get_cached_insight(uuid, text, timestamptz, timestamptz);
CREATE OR REPLACE FUNCTION get_cached_insight(
  p_user_id uuid,
  p_insight_type text,
  p_date_start timestamptz DEFAULT NULL,
  p_date_end timestamptz DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  content jsonb,
  generated_at timestamptz,
  entries_analyzed_count int
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ui.id,
    ui.content,
    ui.generated_at,
    ui.entries_analyzed_count
  FROM user_insights ui
  WHERE ui.user_id = p_user_id
    AND ui.insight_type = p_insight_type
    AND ui.is_valid = true
    AND (ui.expires_at IS NULL OR ui.expires_at > now())
    AND (p_date_start IS NULL OR ui.date_range_start = p_date_start)
    AND (p_date_end IS NULL OR ui.date_range_end = p_date_end)
  ORDER BY ui.generated_at DESC
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to save insight to cache
CREATE OR REPLACE FUNCTION save_insight_cache(
  p_user_id uuid,
  p_insight_type text,
  p_content jsonb,
  p_entries_count int,
  p_date_start timestamptz DEFAULT NULL,
  p_date_end timestamptz DEFAULT NULL,
  p_ttl_hours int DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
  new_id uuid;
  expires timestamptz;
BEGIN
  -- Calculate expiry if TTL provided
  IF p_ttl_hours IS NOT NULL THEN
    expires := now() + (p_ttl_hours || ' hours')::interval;
  END IF;

  -- Insert new insight
  INSERT INTO user_insights (
    user_id,
    insight_type,
    content,
    entries_analyzed_count,
    date_range_start,
    date_range_end,
    expires_at
  ) VALUES (
    p_user_id,
    p_insight_type,
    p_content,
    p_entries_count,
    p_date_start,
    p_date_end,
    expires
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to manually invalidate insights
CREATE OR REPLACE FUNCTION invalidate_insights(
  p_user_id uuid,
  p_insight_type text DEFAULT NULL
)
RETURNS int AS $$
DECLARE
  rows_affected int;
BEGIN
  UPDATE user_insights
  SET is_valid = false
  WHERE user_id = p_user_id
    AND is_valid = true
    AND (p_insight_type IS NULL OR insight_type = p_insight_type);

  GET DIAGNOSTICS rows_affected = ROW_COUNT;
  RETURN rows_affected;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 8. AUTOMATIC CLEANUP FUNCTION (for cron job)
-- ============================================================

-- Function to clean up expired insights
CREATE OR REPLACE FUNCTION cleanup_expired_insights()
RETURNS TABLE (
  deleted_count int,
  oldest_deleted timestamptz
) AS $$
DECLARE
  rows_deleted int;
  oldest_ts timestamptz;
BEGIN
  -- Get oldest timestamp before deletion
  SELECT MIN(created_at) INTO oldest_ts
  FROM user_insights
  WHERE (expires_at IS NOT NULL AND expires_at < now())
     OR (is_valid = false AND updated_at < now() - interval '30 days');

  -- Delete expired and old invalid insights
  DELETE FROM user_insights
  WHERE (expires_at IS NOT NULL AND expires_at < now())
     OR (is_valid = false AND updated_at < now() - interval '30 days');

  GET DIAGNOSTICS rows_deleted = ROW_COUNT;

  RETURN QUERY SELECT rows_deleted, oldest_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. ADD HELPFUL COMMENTS
-- ============================================================

COMMENT ON TABLE user_insights IS 'Cache for expensive AI-generated insights to reduce API calls';
COMMENT ON COLUMN user_insights.insight_type IS 'Type of insight: theme_summary, monthly_insights, weekly_recap, etc.';
COMMENT ON COLUMN user_insights.content IS 'Flexible JSONB structure containing the actual insight data';
COMMENT ON COLUMN user_insights.entries_analyzed_count IS 'Number of entries used to generate this insight';
COMMENT ON COLUMN user_insights.is_valid IS 'False if cache is invalidated by new/updated entries';
COMMENT ON COLUMN user_insights.expires_at IS 'Optional TTL for automatic cache expiry';
COMMENT ON COLUMN user_insights.generation_time_ms IS 'Milliseconds taken to generate insight (for monitoring)';

-- ============================================================
-- 10. VALIDATION
-- ============================================================

DO $$
DECLARE
  index_count INTEGER;
  function_count INTEGER;
BEGIN
  -- Count indexes
  SELECT COUNT(*) INTO index_count
  FROM pg_indexes
  WHERE tablename = 'user_insights';

  -- Count custom functions
  SELECT COUNT(*) INTO function_count
  FROM pg_proc
  WHERE proname LIKE '%insight%';

  RAISE NOTICE '✅ Insights cache table created successfully';
  RAISE NOTICE '   - Table: user_insights';
  RAISE NOTICE '   - Indexes: %', index_count;
  RAISE NOTICE '   - Helper functions: %', function_count;
  RAISE NOTICE '   - Auto-invalidation triggers: 3 (on INSERT, UPDATE, DELETE)';
  RAISE NOTICE '   - Cache types: theme_summary, monthly_insights, weekly_recap, annual_review, custom_query';
END $$;
