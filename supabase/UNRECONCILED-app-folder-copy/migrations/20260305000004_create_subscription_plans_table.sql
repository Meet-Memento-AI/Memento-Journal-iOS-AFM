-- Migration: Create subscription_plans table with seed data

CREATE TABLE subscription_plans (
    id text PRIMARY KEY,
    name text NOT NULL,
    description text,
    price_usd decimal(10,2),
    daily_entry_limit integer,
    daily_ai_insight_limit integer,
    is_active boolean DEFAULT true
);

-- Enable Row Level Security (public read access)
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;

-- Anyone can view plans (public data, no user-specific info)
CREATE POLICY "Anyone can view plans" ON subscription_plans
    FOR SELECT USING (true);

-- Seed initial subscription plans
INSERT INTO subscription_plans (id, name, description, price_usd, daily_entry_limit, daily_ai_insight_limit, is_active) VALUES
    ('free', 'Free', 'Basic journaling', 0.00, 3, 1, true),
    ('pro_monthly', 'Pro Monthly', 'Unlimited journaling', 9.99, NULL, 10, true),
    ('pro_yearly', 'Pro Yearly', 'Unlimited journaling (annual)', 99.99, NULL, 10, true);
