-- Migration: Create ai_feedback table for storing user feedback on AI-generated content

CREATE TABLE ai_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_id uuid NOT NULL,
    target_type text NOT NULL CHECK (target_type IN ('insight', 'followup', 'summary')),
    rating integer CHECK (rating >= 1 AND rating <= 5),
    is_helpful boolean,
    user_comment text,
    created_at timestamptz DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE ai_feedback ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own feedback
CREATE POLICY "Users can view own feedback" ON ai_feedback
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own feedback" ON ai_feedback
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create indexes for efficient queries
CREATE INDEX idx_ai_feedback_user_id ON ai_feedback(user_id);
CREATE INDEX idx_ai_feedback_target ON ai_feedback(target_id, target_type);
