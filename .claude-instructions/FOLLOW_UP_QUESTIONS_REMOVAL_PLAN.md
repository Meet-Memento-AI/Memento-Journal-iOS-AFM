# Follow-Up Questions Feature - Complete Removal Plan

**Date:** October 22, 2025
**Purpose:** Remove all code and infrastructure related to the DigDeeperView AI-generated follow-up questions feature
**Impact:** Will significantly reduce codebase complexity and remove unused backend infrastructure

---

## 📋 Overview

The follow-up questions feature included:
- AI-generated weekly questions based on journal entries
- TF-IDF algorithm for question relevance
- Database storage and completion tracking
- Edge functions for automated question generation
- Success screens and UI components

After pivoting to show InsightsView (themes/summaries) instead of DigDeeperView (questions), this entire system is now unused.

---

## 🗂️ Files to Delete

### 1. ViewModels (2 files)
```
withMemento/ViewModels/
├─ GeneratedQuestionsViewModel.swift  ❌ DELETE
└─ QuestionGenerationTracker.swift    ❌ DELETE (if exists - check first)
```

**Purpose:** Managed AI-generated question state and completion tracking

---

### 2. Models (2 files)
```
withMemento/Models/
├─ GeneratedFollowUpQuestion.swift  ❌ DELETE
└─ FollowUpQuestion.swift          ❌ DELETE
```

**Details:**
- `GeneratedFollowUpQuestion`: AI-generated questions from database
- `FollowUpQuestion`: Legacy hardcoded questions with categories

---

### 3. Services (1-2 files)
```
withMemento/Services/
├─ SupabaseService+FollowUpQuestions.swift  ❌ DELETE
└─ QuestionGenerationTracker.swift          ❌ DELETE (if exists)
```

**Purpose:** Supabase API calls for question CRUD operations

---

### 4. UI Components (3 files)
```
withMemento/Components/Cards/
├─ FollowUpCard.swift          ❌ DELETE
└─ FollowUpQuestionCard.swift  ❌ DELETE

withMemento/Views/Journal/
└─ JournalCreatedView.swift    ❌ DELETE
```

**Details:**
- `FollowUpCard`: Card showing a question with completion state
- `FollowUpQuestionCard`: Alternative card component
- `JournalCreatedView`: Success animation shown after answering a question

---

### 5. Archived Views (1 file)
```
withMemento/Views/Journal/
└─ DigDeeperView.swift.backup  ❌ DELETE
```

**Note:** Already archived, safe to delete permanently

---

### 6. Edge Functions (2 directories)
```
supabase/functions/
├─ generate-follow-up/         ❌ DELETE ENTIRE DIRECTORY
│  ├─ index.ts
│  ├─ tfidf.ts
│  ├─ precompute.ts
│  ├─ question-bank.ts
│  ├─ types.ts
│  └─ (test files, backups)
│
└─ weekly-question-generator/  ❌ DELETE ENTIRE DIRECTORY
   └─ index.ts
```

**Purpose:**
- `generate-follow-up`: TF-IDF algorithm + question generation
- `weekly-question-generator`: Cron job for weekly automation

---

### 7. Database Migrations (4 files)
```
supabase/migrations/
├─ 20250118000000_follow_up_questions_table.sql        ❌ DELETE (or keep for history)
├─ 20251021140000_improve_complete_question_rpc.sql    ❌ DELETE (or keep for history)
└─ 20251021150000_fix_complete_question_rpc.sql        ❌ DELETE (or keep for history)
```

**Decision:**
- **Option A (Recommended):** Keep migration files but comment them out (for historical record)
- **Option B:** Delete entirely if you want a clean slate

**Note:** The `follow_up_questions` table in production database should be dropped via a new migration.

---

### 8. Documentation (6+ files)
```
.claude-instructions/implementations/
├─ IMPLEMENTATION_INSTRUCTIONS.md
├─ CONTINUOUS_QUESTIONS_IMPLEMENTATION.md
├─ BACKGROUND_QUESTION_GENERATION.md
├─ PULL_TO_REFRESH_IMPLEMENTATION.md
└─ FOLLOW_UP_CARD_COMPLETION_IMPROVEMENTS.md

.claude-instructions/setup/
├─ AUTOMATED_QUESTIONS_READY.md
├─ QUICKSTART_WEEKLY_QUESTIONS.md
└─ DEPLOYMENT_STATUS.md (partially related)

.claude-instructions/diagnostics/
├─ TFIDF_REVIEW_AND_IMPROVEMENTS.md
├─ APPLY_TFIDF_FIXES.md
└─ TFIDF_FIXES_APPLIED.md
```

**Action:** Move to `.claude-instructions/archive/follow-up-questions/` for reference

---

## ✏️ Files to Modify (Code Cleanup)

### 1. **ContentView.swift**
**Remove:**
- Line 14-16: `case followUp(String)` enum case (legacy)
- Line 17: `case followUpGenerated(...)` enum case (database)
- Lines 81-112: Both followUp route handlers in navigationDestination
- Lines 131-139: `showJournalCreated` state and fullScreenCover

**Keep:**
- `case create` and `case edit(Entry)` routes

**Before:**
```swift
public enum EntryRoute: Hashable {
    case create
    case edit(Entry)
    case followUp(String)
    case followUpGenerated(questionText: String, questionId: UUID)
}

@State private var showJournalCreated = false

// navigationDestination handlers for followUp cases
// fullScreenCover for JournalCreatedView
```

**After:**
```swift
public enum EntryRoute: Hashable {
    case create
    case edit(Entry)
}

// Remove showJournalCreated state
// Remove followUp navigationDestination handlers
// Remove JournalCreatedView fullScreenCover
```

---

### 2. **AddEntryView.swift**
**Remove:**
- Line 15: `case followUp(questionText: String, questionId: UUID?)` from EntryState enum
- Lines 52-54: followUp initialization case
- Lines 60-78: All computed properties (isFollowUpEntry, followUpQuestionText, questionId)
- Line 35: Remove `questionId` parameter from onSave callback

**Before:**
```swift
public enum EntryState: Hashable {
    case create
    case edit(Entry)
    case followUp(questionText: String, questionId: UUID?)
}

let onSave: (_ title: String, _ text: String, _ questionId: UUID?) -> Void
```

**After:**
```swift
public enum EntryState: Hashable {
    case create
    case edit(Entry)
}

let onSave: (_ title: String, _ text: String) -> Void
```

---

### 3. **EntryViewModel.swift**
**Remove:**
- Line 17: `completedFollowUpQuestions` property (legacy tracking)
- Lines 21-22: `questionsViewModel` property (database tracking)
- Lines 164-254: Entire `createFollowUpEntry` method
- Lines 296-338: `allFollowUpQuestions` computed property (if exists)

**Keep:**
- `createEntry` method (regular journal entries)
- `updateEntry`, `deleteEntry`, `loadEntries` methods

**Impact:** Simplifies ViewModel by ~100 lines

---

### 4. **Entry.swift**
**Decision Required:**

**Option A (Minimal Change):** Keep `isFollowUp` field but stop using it
```swift
public var isFollowUp: Bool // Keep for backward compatibility
```

**Option B (Clean Removal):** Remove field entirely
```swift
// Remove isFollowUp field
// Remove from CodingKeys
// Remove from init
// Remove from decoder
```

**Recommendation:** Option B - clean removal, but requires database column removal

---

### 5. **SupabaseService.swift**
**Check for:**
- Any follow-up question related methods that might be defined in the main service file
- Import statements for `SupabaseService+FollowUpQuestions`

**Remove:** Any imports or extensions referencing follow-up questions

---

### 6. **Theme.swift** (Check Only)
**Search for:**
```swift
// Look for any follow-up specific color definitions
```

**Action:** Remove if found (unlikely, but check)

---

## 🗄️ Database Cleanup

### Create New Migration: `drop_follow_up_questions.sql`

```sql
-- Drop follow_up_questions table and related objects
-- Run this AFTER deploying code changes

-- Drop RPC functions
DROP FUNCTION IF EXISTS complete_follow_up_question(uuid, uuid);
DROP FUNCTION IF EXISTS get_current_week_questions();

-- Drop indexes
DROP INDEX IF EXISTS idx_follow_up_questions_user_week;
DROP INDEX IF EXISTS idx_follow_up_questions_completion;

-- Drop table
DROP TABLE IF EXISTS follow_up_questions;

-- Drop any related policies (RLS)
-- (These will auto-drop with the table, but explicit for clarity)
DROP POLICY IF EXISTS "Users can view own questions" ON follow_up_questions;
DROP POLICY IF EXISTS "Users can update own questions" ON follow_up_questions;

-- Optional: Drop entries.is_follow_up column
ALTER TABLE entries DROP COLUMN IF EXISTS is_follow_up;
```

**Deployment Order:**
1. ✅ Deploy code changes first (remove all Swift code)
2. ✅ Test app thoroughly without follow-up features
3. ✅ Run database migration to drop tables
4. ✅ Undeploy edge functions from Supabase dashboard

---

## 📊 Impact Analysis

### Lines of Code Removed
| Category | Files | Est. Lines |
|----------|-------|------------|
| ViewModels | 2 | ~350 |
| Models | 2 | ~150 |
| Services | 1-2 | ~200 |
| UI Components | 3 | ~400 |
| Views | 1 | ~360 |
| Edge Functions | 2 dirs | ~1500 |
| Code cleanup | 4 files | ~200 |
| **TOTAL** | **~15 files** | **~3,160 lines** |

### Benefits
✅ **Reduced complexity** - Remove entire question generation subsystem
✅ **Faster builds** - Fewer files to compile
✅ **Lower Supabase costs** - Remove edge function execution
✅ **Cleaner codebase** - Easier to understand and maintain
✅ **No database overhead** - Remove follow_up_questions table

### Risks
⚠️ **Breaking changes** - Existing users with questions will lose them
⚠️ **Database migration required** - Must carefully drop tables
⚠️ **No rollback path** - Once removed, difficult to restore

---

## 🚀 Execution Plan

### Phase 1: Backup (5 minutes)
```bash
# Create backup branch
git checkout -b backup/follow-up-questions-removal
git push -u origin backup/follow-up-questions-removal

# Export database schema
supabase db dump -f backup_schema.sql

# Return to main branch
git checkout Memento-v1.0
```

---

### Phase 2: Delete Files (10 minutes)

```bash
cd /Users/sebastianmendo/Swift-projects/withMemento

# ViewModels
git rm withMemento/ViewModels/GeneratedQuestionsViewModel.swift
git rm withMemento/ViewModels/QuestionGenerationTracker.swift  # if exists

# Models
git rm withMemento/Models/GeneratedFollowUpQuestion.swift
git rm withMemento/Models/FollowUpQuestion.swift

# Services
git rm withMemento/Services/SupabaseService+FollowUpQuestions.swift

# UI Components
git rm withMemento/Components/Cards/FollowUpCard.swift
git rm withMemento/Components/Cards/FollowUpQuestionCard.swift
git rm withMemento/Views/Journal/JournalCreatedView.swift

# Archived view
git rm withMemento/Views/Journal/DigDeeperView.swift.backup

# Edge functions
git rm -r supabase/functions/generate-follow-up
git rm -r supabase/functions/weekly-question-generator

# Documentation
mkdir -p .claude-instructions/archive/follow-up-questions
git mv .claude-instructions/implementations/IMPLEMENTATION_INSTRUCTIONS.md \
       .claude-instructions/archive/follow-up-questions/
git mv .claude-instructions/implementations/CONTINUOUS_QUESTIONS_IMPLEMENTATION.md \
       .claude-instructions/archive/follow-up-questions/
# ... (move other related docs)
```

---

### Phase 3: Code Cleanup (30 minutes)

**Edit files in this order:**

1. **ContentView.swift**
   - Remove followUp enum cases
   - Remove showJournalCreated state
   - Remove navigationDestination handlers
   - Remove fullScreenCover

2. **AddEntryView.swift**
   - Remove followUp EntryState case
   - Remove questionId from onSave
   - Update all onSave calls

3. **EntryViewModel.swift**
   - Remove completedFollowUpQuestions
   - Remove questionsViewModel
   - Remove createFollowUpEntry method
   - Remove allFollowUpQuestions computed property

4. **Entry.swift**
   - Remove isFollowUp field
   - Remove from CodingKeys
   - Remove from init
   - Remove from decoder

5. **SupabaseService.swift**
   - Remove any follow-up imports

---

### Phase 4: Build & Test (15 minutes)

```bash
# Clean build
xcodebuild clean

# Build project
xcodebuild -scheme withMemento -destination 'generic/platform=iOS' build

# Run tests (if you have any)
xcodebuild test -scheme withMemento -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# Manual testing checklist:
# [ ] App launches without crashes
# [ ] Can create regular journal entries
# [ ] Can edit existing entries
# [ ] Can delete entries
# [ ] Journal tab shows entries correctly
# [ ] Insights tab shows themes/summaries
# [ ] Settings work
# [ ] Dark mode works
```

---

### Phase 5: Database Cleanup (10 minutes)

```bash
# Create migration
supabase migration new drop_follow_up_questions

# Edit the migration file with SQL from above

# Apply migration to local dev
supabase db reset

# Test app with clean database

# Deploy to production (when ready)
supabase db push
```

---

### Phase 6: Commit & Deploy (5 minutes)

```bash
# Stage all changes
git add -A

# Commit
git commit -m "Remove follow-up questions feature

- Delete GeneratedQuestionsViewModel, models, and services
- Remove FollowUpCard, JournalCreatedView UI components
- Remove followUp routes from ContentView and AddEntryView
- Clean up EntryViewModel (remove createFollowUpEntry)
- Remove Entry.isFollowUp field
- Delete edge functions (generate-follow-up, weekly-question-generator)
- Archive related documentation

Reduces codebase by ~3,160 lines
Part of layout pivot to Insights view"

# Push
git push origin Memento-v1.0
```

---

## ✅ Testing Checklist

After removal, verify:

### Core Functionality
- [ ] App launches successfully
- [ ] No compilation errors or warnings
- [ ] No runtime crashes

### Journal Features
- [ ] Can create new journal entries
- [ ] Can edit existing entries
- [ ] Can delete entries
- [ ] Entries display correctly in list
- [ ] Month grouping works

### Navigation
- [ ] Top tabs (Journal/Insights) work
- [ ] FAB button creates entries
- [ ] Settings navigation works
- [ ] Back navigation works

### Insights Tab
- [ ] Shows themes/summaries correctly
- [ ] Empty state displays properly

### Entry Creation
- [ ] Title and body fields work
- [ ] Save button works
- [ ] Cancel/back works
- [ ] Keyboard dismissal works

### Edge Cases
- [ ] Empty database state
- [ ] Network error handling
- [ ] Sign out works
- [ ] Dark mode works

---

## 📝 Notes

### Why Keep Some Migrations?
Keeping old migration files (commented out) provides:
- Historical record of database schema evolution
- Easier debugging if issues arise
- Documentation of what was tried

### Why Remove JournalCreatedView?
The success animation was specifically designed for answering follow-up questions. Without that feature, it's just unnecessary complexity.

### Alternative: Feature Flag
If you might want to bring this back later, consider:
```swift
struct FeatureFlags {
    static let followUpQuestionsEnabled = false
}
```

But for maximum cleanup, complete removal is recommended.

---

## 🎯 Success Criteria

**Done when:**
1. ✅ All follow-up question files deleted
2. ✅ No compilation errors
3. ✅ App runs without crashes
4. ✅ All tests pass
5. ✅ Database migration applied
6. ✅ Edge functions undeployed
7. ✅ Code review complete
8. ✅ Changes committed and pushed

**Estimated Total Time:** ~1.5 hours

---

## 🔄 Rollback Procedure

If issues occur:

```bash
# Restore from backup branch
git checkout backup/follow-up-questions-removal
git checkout -b rollback/restore-follow-up

# Cherry-pick specific fixes if needed
git cherry-pick <commit-hash>

# Or full reset
git reset --hard <commit-before-removal>
```

---

**Status:** 📋 **READY FOR EXECUTION**
**Priority:** Medium (cleanup, not urgent)
**Complexity:** Medium (requires careful testing)
