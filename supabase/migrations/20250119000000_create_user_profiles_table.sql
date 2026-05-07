-- ============================================================
-- Migration: Create user_profiles table (foundational)
-- This should run BEFORE the theme analysis migrations
-- ============================================================

-- ============================================================
-- CREATE USER_PROFILES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- ENSURE ALL AUTH USERS HAVE PROFILES
-- ============================================================
DO $$
DECLARE
  fk_targets_auth_users boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint constraint_def
    JOIN pg_class table_def ON table_def.oid = constraint_def.conrelid
    JOIN pg_namespace table_ns ON table_ns.oid = table_def.relnamespace
    JOIN pg_attribute column_def
      ON column_def.attrelid = table_def.oid
      AND column_def.attnum = ANY (constraint_def.conkey)
    JOIN pg_class referenced_table ON referenced_table.oid = constraint_def.confrelid
    JOIN pg_namespace referenced_ns ON referenced_ns.oid = referenced_table.relnamespace
    WHERE constraint_def.contype = 'f'
      AND table_ns.nspname = 'public'
      AND table_def.relname = 'user_profiles'
      AND column_def.attname = 'user_id'
      AND referenced_ns.nspname = 'auth'
      AND referenced_table.relname = 'users'
  ) INTO fk_targets_auth_users;

  IF fk_targets_auth_users THEN
    INSERT INTO user_profiles (user_id)
    SELECT auth_user.id
    FROM auth.users AS auth_user
    WHERE NOT EXISTS (
      SELECT 1
      FROM user_profiles AS profile
      WHERE profile.user_id = auth_user.id
    )
    ON CONFLICT (user_id) DO NOTHING;
  ELSE
    RAISE NOTICE 'Skipping user_profiles auth.users backfill because existing foreign key target is not auth.users';
  END IF;
END $$;

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION update_user_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_profiles_updated_at ON user_profiles;
CREATE TRIGGER trigger_update_user_profiles_updated_at
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_user_profiles_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;

CREATE POLICY "Users can view own profile"
  ON user_profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own profile"
  ON user_profiles FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile"
  ON user_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- VALIDATION
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE '✅ user_profiles table created successfully';
END $$;
