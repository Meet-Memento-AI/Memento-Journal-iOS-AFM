-- ============================================================
-- Migration: RAG Chat Schema
-- Purpose: pgvector embeddings on journal_entries, similarity
--          search function, chat_messages table, and auto-reset
--          trigger for re-embedding on content edits.
-- Date: 2026-03-05
-- ============================================================

-- ============================================================
-- 1. Enable pgvector extension
-- ============================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- 2. Add embedding columns to journal_entries
-- ============================================================

ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS embedding vector(768),
  ADD COLUMN IF NOT EXISTS embedding_status TEXT NOT NULL DEFAULT 'pending';

-- updated_at may already exist from a prior migration; add only if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'journal_entries' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE journal_entries ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
  END IF;
END $$;

-- ============================================================
-- 3. Vector similarity search function (pgvector)
-- ============================================================

CREATE OR REPLACE FUNCTION match_journal_entries(
  query_embedding vector(768),
  match_user_id UUID,
  match_count INT DEFAULT 5,
  match_threshold FLOAT DEFAULT 0.3
)
RETURNS TABLE (
  id UUID,
  content TEXT,
  created_at TIMESTAMPTZ,
  similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    je.id,
    je.content,
    je.created_at,
    (1 - (je.embedding <=> query_embedding))::FLOAT AS similarity
  FROM journal_entries je
  WHERE je.user_id = match_user_id
    AND je.embedding IS NOT NULL
    AND je.embedding_status = 'complete'
    AND je.is_deleted = false
    AND (1 - (je.embedding <=> query_embedding)) > match_threshold
  ORDER BY je.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- ============================================================
-- 4. chat_messages table
-- ============================================================

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_messages_user_created_idx
  ON chat_messages(user_id, created_at DESC);

-- Row Level Security
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own messages" ON chat_messages;
CREATE POLICY "Users read own messages"
  ON chat_messages FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own messages" ON chat_messages;
CREATE POLICY "Users insert own messages"
  ON chat_messages FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users delete own messages" ON chat_messages;
CREATE POLICY "Users delete own messages"
  ON chat_messages FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 5. Auto-reset embedding when entry content changes
-- ============================================================

CREATE OR REPLACE FUNCTION reset_embedding_on_update()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.content IS DISTINCT FROM OLD.content THEN
    NEW.embedding_status := 'pending';
    NEW.embedding := NULL;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reset_embedding ON journal_entries;
CREATE TRIGGER trg_reset_embedding
  BEFORE UPDATE ON journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION reset_embedding_on_update();

-- ============================================================
-- 6. Mark existing entries for backfill
-- ============================================================

UPDATE journal_entries
  SET embedding_status = 'pending'
  WHERE embedding IS NULL
    AND is_deleted = false;
