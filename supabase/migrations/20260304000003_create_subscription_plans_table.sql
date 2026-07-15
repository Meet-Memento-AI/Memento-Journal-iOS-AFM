-- Migration: create public.subscription_plans (spec-003 R1/R2).
--
-- Adopted from the nested copy at
-- supabase/UNRECONCILED-app-folder-copy/migrations/20260305000004_...sql,
-- deployed to prod the same day as its siblings (rename, users, ai_feedback).
--
-- NOTE: as of this migration, no service layer queries this table — only the
-- `SubscriptionPlan` Swift model (MeetMemento/Models/SubscriptionPlan.swift)
-- references it, with zero call sites (no monetization flow wired up yet).
-- Global reference/catalog data, not user-owned — excluded from the account
-- deletion cascade audit. Adopted for schema reproducibility; confirm with
-- `supabase db diff --linked` whether prod truly has it.

CREATE TABLE IF NOT EXISTS public.subscription_plans (
    id text PRIMARY KEY,
    name text NOT NULL,
    description text,
    price_usd decimal(10,2),
    daily_entry_limit integer,
    daily_ai_insight_limit integer,
    is_active boolean DEFAULT true
);

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view plans" ON public.subscription_plans;
CREATE POLICY "Anyone can view plans" ON public.subscription_plans
    FOR SELECT USING (true);

INSERT INTO public.subscription_plans (id, name, description, price_usd, daily_entry_limit, daily_ai_insight_limit, is_active) VALUES
    ('free', 'Free', 'Basic journaling', 0.00, 3, 1, true),
    ('pro_monthly', 'Pro Monthly', 'Unlimited journaling', 9.99, NULL, 10, true),
    ('pro_yearly', 'Pro Yearly', 'Unlimited journaling (annual)', 99.99, NULL, 10, true)
ON CONFLICT (id) DO NOTHING;
