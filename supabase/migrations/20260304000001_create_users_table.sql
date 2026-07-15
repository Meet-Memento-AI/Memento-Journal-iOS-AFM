-- Migration: create public.users (spec-003 R1/R2/R3).
--
-- Adopted from the nested copy at
-- supabase/UNRECONCILED-app-folder-copy/migrations/20260305000002_...sql.
-- Live app code depends on this table today (UserService.swift, AuthViewModel.swift
-- all query `.from("users")`), and delete_user() references it — so its absence
-- from the canonical chain is exactly the reproducibility bug spec 003 exists to fix.

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email text NOT NULL,
    full_name text,
    avatar_url text,
    preferences jsonb DEFAULT '{}',
    goals text,
    selected_topics text[],
    onboarding_completed boolean NOT NULL DEFAULT false,
    onboarding_completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile" ON public.users;
CREATE POLICY "Users can view own profile" ON public.users
    FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
CREATE POLICY "Users can update own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
CREATE POLICY "Users can insert own profile" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Named per-table (not the generic update_updated_at_column()) because that
-- generic function was deliberately dropped in
-- 20251023000000_cleanup_deprecated_schema.sql in favor of per-table triggers.
CREATE OR REPLACE FUNCTION public.update_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_users_updated_at ON public.users;
CREATE TRIGGER trigger_update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.update_users_updated_at();

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
