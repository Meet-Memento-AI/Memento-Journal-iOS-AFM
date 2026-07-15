-- Migration: per-user rate-limit log for LLM edge functions (spec-004 R2)
-- Idempotent. Slots after the reconciled baseline (spec 003).

CREATE TABLE IF NOT EXISTS public.rate_limits (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    function_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Fast window lookups per (user, function).
CREATE INDEX IF NOT EXISTS idx_rate_limits_lookup
    ON public.rate_limits (user_id, function_name, created_at DESC);

ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- Users may only read/insert their own rate-limit rows, so the edge functions'
-- user-scoped client (caller JWT) can enforce limits without the service-role key.
DROP POLICY IF EXISTS "rate_limits_select_own" ON public.rate_limits;
CREATE POLICY "rate_limits_select_own" ON public.rate_limits
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "rate_limits_insert_own" ON public.rate_limits;
CREATE POLICY "rate_limits_insert_own" ON public.rate_limits
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Housekeeping: prune old rows (safe to run repeatedly). Callers may also rely on
-- a scheduled job; this function lets a cron/pg_cron or manual call keep it small.
CREATE OR REPLACE FUNCTION public.prune_rate_limits(older_than interval DEFAULT interval '2 days')
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    DELETE FROM public.rate_limits WHERE created_at < now() - older_than;
$$;

REVOKE EXECUTE ON FUNCTION public.prune_rate_limits(interval) FROM anon;
GRANT EXECUTE ON FUNCTION public.prune_rate_limits(interval) TO service_role;
