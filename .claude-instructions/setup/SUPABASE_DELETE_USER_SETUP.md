# Supabase User Deletion Setup

## Overview

withMemento already has account deletion code implemented in `SupabaseService.swift`, but it requires a database function in Supabase to fully delete the auth account.

**Current Implementation:**
1. ✅ Deletes all journal entries from `entries` table
2. ⚠️ Tries to delete auth account via `delete_user()` RPC function (needs to be created)
3. ✅ Clears user_metadata (happens automatically when auth account is deleted)

---

## 🔧 Setup Instructions

### **Step 1: Open Supabase Dashboard**

1. Go to https://supabase.com/dashboard
2. Select your withMemento project
3. Click **"SQL Editor"** in the left sidebar

---

### **Step 2: Create the `delete_user` Function**

Copy and paste this SQL into the SQL Editor and click **"Run"**:

```sql
-- Create a function to delete the current authenticated user
-- This function runs with elevated permissions (SECURITY DEFINER)
-- and can only be called by authenticated users

CREATE OR REPLACE FUNCTION delete_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  -- Get the current authenticated user's ID
  current_user_id := auth.uid();

  -- Ensure user is authenticated
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Delete all user data from entries table (if not already deleted by app)
  DELETE FROM public.entries WHERE user_id = current_user_id;

  -- Delete the user from auth.users
  -- This also deletes user_metadata automatically
  DELETE FROM auth.users WHERE id = current_user_id;

  -- Log the deletion (optional, for debugging)
  RAISE NOTICE 'User % deleted successfully', current_user_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_user() TO authenticated;

-- Revoke from anonymous users (extra security)
REVOKE EXECUTE ON FUNCTION delete_user() FROM anon;
```

---

### **Step 3: Verify the Function Was Created**

After running the SQL, verify it was created:

```sql
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'delete_user';
```

You should see:
```
routine_name | routine_type
delete_user  | FUNCTION
```

---

### **Step 4: Test Account Deletion**

1. Run your withMemento app
2. Create a test account via onboarding
3. Go to **Settings → Danger Zone → Delete Account**
4. Confirm deletion
5. Check the logs - you should see:
   ```
   🗑️ Deleted all entries for user: [UUID]
   ✅ User account fully deleted from auth: [UUID]
   ```

---

## 🔍 What This Function Does

### **Security Features:**

1. **`SECURITY DEFINER`**: Runs with the permissions of the function creator (you/admin), not the caller
   - Needed because normal users can't delete from `auth.users` directly

2. **`auth.uid()` Check**: Only deletes the currently authenticated user
   - User can only delete their own account, not others

3. **`GRANT EXECUTE TO authenticated`**: Only logged-in users can call this
   - Anonymous users cannot delete accounts

### **What Gets Deleted:**

1. **All journal entries** from `entries` table where `user_id` matches
2. **User metadata** from `auth.users.user_metadata` (onboarding data, name, etc.)
3. **Auth account** from `auth.users` (email, password hash, etc.)

### **Order of Operations:**

```
App calls deleteAccount()
    ↓
1. Delete from entries table (client SDK)
    ↓
2. Call delete_user() RPC function
    ↓
3. Function deletes from entries (redundant, but safe)
    ↓
4. Function deletes from auth.users
    ↓
5. App signs out user
    ↓
User account completely removed ✅
```

---

## 📊 Current Database Tables

### **1. `entries` table**
Stores journal entries. Schema:
```sql
CREATE TABLE entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  title TEXT,
  text TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

**Deletion:** ✅ Handled by app + function

---

### **2. `auth.users` table (Supabase managed)**
Stores authentication data. Includes:
- `id` (UUID)
- `email`
- `encrypted_password`
- `user_metadata` (JSONB) - stores:
  - `first_name`
  - `last_name`
  - `user_personalization_text`
  - `selected_themes`
  - `onboarding_completed`

**Deletion:** ✅ Handled by function

---

## 🧪 Testing Checklist

### **Before Testing:**
- [ ] SQL function created in Supabase
- [ ] Function verified with SELECT query
- [ ] App is running

### **Test Case 1: Delete Account with Entries**
1. [ ] Create test account
2. [ ] Complete onboarding
3. [ ] Create 2-3 journal entries
4. [ ] Go to Settings → Delete Account
5. [ ] Confirm deletion
6. [ ] Verify success message
7. [ ] Verify redirect to WelcomeView
8. [ ] Check Supabase Dashboard:
   - [ ] User NOT in Authentication → Users
   - [ ] Entries NOT in Table Editor → entries

### **Test Case 2: Delete Account During Onboarding**
1. [ ] Create test account
2. [ ] Complete profile step only (don't finish onboarding)
3. [ ] Force quit app
4. [ ] Reopen app → Should show onboarding
5. [ ] Go to Settings → Delete Account (may not have this option yet)
6. [ ] If available, delete and verify

### **Test Case 3: Delete Account with No Entries**
1. [ ] Create test account
2. [ ] Complete onboarding
3. [ ] Don't create any entries
4. [ ] Go to Settings → Delete Account
5. [ ] Confirm deletion
6. [ ] Verify success message
7. [ ] Verify user deleted from Supabase

---

## ⚠️ Important Notes

### **Data is Permanently Deleted**
- There is NO undo or recovery
- This is by design (GDPR compliance)
- Perfect for testing, but remind users in production!

### **If Function Creation Fails**
If you get an error creating the function:

1. **Permission Error:** You need to be the project owner
2. **Already Exists:** Drop it first:
   ```sql
   DROP FUNCTION IF EXISTS delete_user();
   ```
   Then re-run the CREATE FUNCTION statement

3. **Syntax Error:** Make sure you copied the entire SQL block

### **If Deletion Fails at Runtime**

Check the app logs. If you see:
```
⚠️ Could not delete auth account (RPC function may not exist)
```

This means:
1. The `delete_user()` function wasn't created in Supabase
2. Or there's a permissions issue

**Fix:** Follow Step 2 above to create the function

---

## 🔐 Production Considerations

### **For Production Release:**

1. **Add Confirmation Email** (future enhancement)
   - Send email before deletion
   - User must confirm via link
   - Prevents accidental deletion

2. **Soft Delete Option** (future enhancement)
   - Mark account as `deleted` instead of hard delete
   - Keep data for 30 days
   - Allow recovery within grace period

3. **Export Data First** (recommended)
   - Let user export their journal entries
   - Download as JSON or PDF
   - Then delete account

4. **Audit Log** (optional)
   - Log deletion events to separate table
   - Track when/why accounts deleted
   - Useful for analytics

---

## 📝 Code Reference

**Current Implementation:**

**File:** `SupabaseService.swift:424-464`
```swift
func deleteAccount() async throws {
    guard let client = client else {
        throw SupabaseServiceError.clientNotConfigured
    }

    // Get user ID before deleting
    let userId = try await getCurrentUserId()

    // Step 1: Delete all user entries from database
    do {
        try await client
            .from("entries")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()

        AppLogger.log("🗑️ Deleted all entries for user: \(userId)", category: AppLogger.network)
    } catch {
        AppLogger.log("❌ Failed to delete user entries: \(error.localizedDescription)",
                     category: AppLogger.network,
                     type: .error)
        throw error
    }

    // Step 2: Try to delete user account from auth
    do {
        try await client.rpc("delete_user").execute()
        AppLogger.log("✅ User account fully deleted from auth: \(userId)", category: AppLogger.network)
    } catch {
        // If delete_user function doesn't exist, that's okay - user data is deleted
        AppLogger.log("⚠️ Could not delete auth account (RPC function may not exist). User data has been deleted.",
                     category: AppLogger.network,
                     type: .default)
        // Don't throw - allow the process to continue since data is deleted
    }

    // Clear cached user ID
    cachedUserId = nil
}
```

**No code changes needed** - just create the Supabase function! ✅

---

## ✅ Summary

1. **Create SQL function** in Supabase Dashboard (Step 2)
2. **Test account deletion** in the app
3. **Verify in Supabase Dashboard** that user and data are gone
4. **Repeat for testing** - create and delete as many accounts as needed!

**Status:** Ready to implement
**Estimated Time:** 5 minutes
**Difficulty:** Easy (copy-paste SQL)

---

**Date Created:** October 16, 2025
**Documentation By:** Claude Code
