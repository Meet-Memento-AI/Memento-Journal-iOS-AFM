-- Migration: harden match_journal_entries (spec-004 R4). Idempotent (CREATE OR REPLACE).
--
-- Defense-in-depth: the RPC already ran as SECURITY INVOKER (RLS applies), but it
-- trusted a caller-supplied match_user_id. Pin retrieval to auth.uid() so a caller
-- can never request another user's rows even if RLS were ever misconfigured, set an
-- explicit search_path, and lock EXECUTE to authenticated users.

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
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- Ignore a spoofed match_user_id: always scope to the caller.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF match_user_id IS DISTINCT FROM auth.uid() THEN
    match_user_id := auth.uid();
  END IF;

  RETURN QUERY
  SELECT
    je.id,
    je.content,
    je.created_at,
    (1 - (je.embedding <=> query_embedding))::FLOAT AS similarity
  FROM journal_entries je
  WHERE je.user_id = auth.uid()
    AND je.embedding IS NOT NULL
    AND je.embedding_status = 'complete'
    AND je.is_deleted = false
    AND (1 - (je.embedding <=> query_embedding)) > match_threshold
  ORDER BY je.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION match_journal_entries(vector, UUID, INT, FLOAT) FROM anon, public;
GRANT EXECUTE ON FUNCTION match_journal_entries(vector, UUID, INT, FLOAT) TO authenticated;
