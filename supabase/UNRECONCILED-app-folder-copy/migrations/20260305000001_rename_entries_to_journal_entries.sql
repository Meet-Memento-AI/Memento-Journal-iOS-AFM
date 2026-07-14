-- Migration: Rename entries table to journal_entries and add missing columns
-- This migration preserves all existing data

-- Rename table from entries to journal_entries
ALTER TABLE entries RENAME TO journal_entries;

-- Rename column from text to content
ALTER TABLE journal_entries RENAME COLUMN text TO content;

-- Add missing columns
ALTER TABLE journal_entries ADD COLUMN word_count integer;
ALTER TABLE journal_entries ADD COLUMN sentiment_score double precision;
ALTER TABLE journal_entries ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
ALTER TABLE journal_entries ADD COLUMN deleted_at timestamptz;
ALTER TABLE journal_entries ADD COLUMN content_hash text;

-- Create index for soft-delete queries
CREATE INDEX idx_journal_entries_is_deleted ON journal_entries(is_deleted);

-- Note: PostgreSQL automatically updates indexes when renaming tables
-- RLS policies referencing the old table name will continue to work
