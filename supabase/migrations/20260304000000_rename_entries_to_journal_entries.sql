-- Migration: rename entries -> journal_entries (spec-003 R1/R2).
--
-- Adopted from the nested copy found at
-- supabase/UNRECONCILED-app-folder-copy/migrations/20260305000001_...sql,
-- which was applied to prod by hand outside the canonical migration chain.
-- This makes that prod-only change a real, ordered, idempotent migration so
-- a fresh `supabase db reset` produces the same schema prod already has.
--
-- Idempotency: every step is guarded so this is a no-op on a database where
-- the rename/columns already exist (prod), while still doing the full rename
-- on a fresh replay (local reset, CI, disaster recovery).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'entries'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'journal_entries'
  ) THEN
    ALTER TABLE public.entries RENAME TO journal_entries;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'text'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'journal_entries' AND column_name = 'content'
  ) THEN
    ALTER TABLE public.journal_entries RENAME COLUMN text TO content;
  END IF;
END $$;

ALTER TABLE public.journal_entries ADD COLUMN IF NOT EXISTS word_count integer;
ALTER TABLE public.journal_entries ADD COLUMN IF NOT EXISTS sentiment_score double precision;
ALTER TABLE public.journal_entries ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE public.journal_entries ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.journal_entries ADD COLUMN IF NOT EXISTS content_hash text;

CREATE INDEX IF NOT EXISTS idx_journal_entries_is_deleted ON public.journal_entries(is_deleted);
