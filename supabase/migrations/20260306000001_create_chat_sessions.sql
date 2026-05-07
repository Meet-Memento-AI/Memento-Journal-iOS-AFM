-- Migration: Create chat_sessions table for multi-chat support
-- Date: 2026-03-06

-- ============================================================
-- 1. CREATE CHAT_SESSIONS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS chat_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS chat_sessions_user_id_idx ON chat_sessions(user_id);
CREATE INDEX IF NOT EXISTS chat_sessions_user_updated_idx ON chat_sessions(user_id, updated_at DESC);

-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;

-- Users can only read their own sessions
DROP POLICY IF EXISTS "Users read own sessions" ON chat_sessions;
CREATE POLICY "Users read own sessions"
  ON chat_sessions FOR SELECT
  USING (auth.uid() = user_id);

-- Users can only insert sessions for themselves
DROP POLICY IF EXISTS "Users insert own sessions" ON chat_sessions;
CREATE POLICY "Users insert own sessions"
  ON chat_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can only update their own sessions
DROP POLICY IF EXISTS "Users update own sessions" ON chat_sessions;
CREATE POLICY "Users update own sessions"
  ON chat_sessions FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can only delete their own sessions
DROP POLICY IF EXISTS "Users delete own sessions" ON chat_sessions;
CREATE POLICY "Users delete own sessions"
  ON chat_sessions FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 4. ADD SESSION_ID FK TO CHAT_MESSAGES
-- ============================================================

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES chat_sessions(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS chat_messages_session_id_idx ON chat_messages(session_id);

-- ============================================================
-- 5. MIGRATE EXISTING MESSAGES TO DEFAULT SESSIONS
-- ============================================================

DO $$
DECLARE
  user_record RECORD;
  new_session_id UUID;
  first_message_content TEXT;
BEGIN
  -- For each user who has chat messages without a session_id
  FOR user_record IN
    SELECT DISTINCT user_id
    FROM chat_messages
    WHERE session_id IS NULL
  LOOP
    -- Get the first message content for this user to use as title
    SELECT content INTO first_message_content
    FROM chat_messages
    WHERE user_id = user_record.user_id AND role = 'user' AND session_id IS NULL
    ORDER BY created_at ASC
    LIMIT 1;

    -- Default title if no user message found
    IF first_message_content IS NULL THEN
      first_message_content := 'Previous conversation';
    END IF;

    -- Truncate to reasonable title length
    first_message_content := LEFT(first_message_content, 100);

    -- Create a session for this user
    INSERT INTO chat_sessions (user_id, title)
    VALUES (user_record.user_id, first_message_content)
    RETURNING id INTO new_session_id;

    -- Assign all orphan messages to this session
    UPDATE chat_messages
    SET session_id = new_session_id
    WHERE user_id = user_record.user_id AND session_id IS NULL;
  END LOOP;
END $$;

-- ============================================================
-- 6. TRIGGER FOR UPDATED_AT
-- ============================================================

-- Create function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_chat_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on chat_sessions
DROP TRIGGER IF EXISTS chat_sessions_updated_at_trigger ON chat_sessions;
CREATE TRIGGER chat_sessions_updated_at_trigger
  BEFORE UPDATE ON chat_sessions
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_sessions_updated_at();

-- Create function to update session's updated_at when a message is added
CREATE OR REPLACE FUNCTION update_session_on_message()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.session_id IS NOT NULL THEN
    UPDATE chat_sessions
    SET updated_at = now()
    WHERE id = NEW.session_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on chat_messages
DROP TRIGGER IF EXISTS chat_messages_session_update_trigger ON chat_messages;
CREATE TRIGGER chat_messages_session_update_trigger
  AFTER INSERT ON chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION update_session_on_message();
