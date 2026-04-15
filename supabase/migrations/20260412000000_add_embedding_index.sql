-- Migration: Add HNSW index for vector similarity search
-- Created: 2026-04-12
-- Purpose: Fix RAG retrieval performance by adding proper vector index

-- Add HNSW index for fast vector similarity search
-- Parameters: m=16 (connections per layer), ef_construction=64 (build-time search width)
CREATE INDEX IF NOT EXISTS idx_journal_entries_embedding_hnsw
  ON journal_entries USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Verify RLS policies exist on journal_entries
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'journal_entries'
  ) THEN
    -- Re-create RLS policies if missing
    ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;

    CREATE POLICY "Users can view own entries"
      ON journal_entries FOR SELECT USING (auth.uid() = user_id);
    CREATE POLICY "Users can insert own entries"
      ON journal_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
    CREATE POLICY "Users can update own entries"
      ON journal_entries FOR UPDATE USING (auth.uid() = user_id);
    CREATE POLICY "Users can delete own entries"
      ON journal_entries FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;
