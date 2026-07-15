-- Migration: create public.ai_feedback (spec-003 R1/R2).
--
-- Adopted from the nested copy at
-- supabase/UNRECONCILED-app-folder-copy/migrations/20260305000003_...sql,
-- deployed to prod the same day as the entries rename and users table.
--
-- NOTE: as of this migration, no service layer queries this table — only the
-- `AIFeedback` Swift model (MeetMemento/Models/AIFeedback.swift) references it,
-- with zero call sites. `chat_feedback` (20260413000000_chat_feedback.sql) is the
-- table actually wired up for AI-response feedback. Adopted here for schema
-- reproducibility (it was very likely applied to prod by hand alongside its
-- siblings); confirm with `supabase db diff --linked` whether prod truly has it,
-- and drop this migration in a follow-up if it doesn't.

CREATE TABLE IF NOT EXISTS public.ai_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_id uuid NOT NULL,
    target_type text NOT NULL CHECK (target_type IN ('insight', 'followup', 'summary')),
    rating integer CHECK (rating >= 1 AND rating <= 5),
    is_helpful boolean,
    user_comment text,
    created_at timestamptz DEFAULT now()
);

ALTER TABLE public.ai_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own feedback" ON public.ai_feedback;
CREATE POLICY "Users can view own feedback" ON public.ai_feedback
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own feedback" ON public.ai_feedback;
CREATE POLICY "Users can insert own feedback" ON public.ai_feedback
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_ai_feedback_user_id ON public.ai_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_target ON public.ai_feedback(target_id, target_type);
