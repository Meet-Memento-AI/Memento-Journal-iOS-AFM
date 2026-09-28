# Implementation Instructions: Continuous Weekly Question Generation

**Option 2: Scheduled Weekly Generation**

This guide walks you through deploying and testing the automated weekly follow-up question system.

---

## Overview

This system will:
- ✅ Automatically generate 5 personalized questions every Sunday at 9 PM
- ✅ Analyze user's journal entries from the last 14 days (sliding window)
- ✅ Store questions in Supabase database
- ✅ Allow users to see new questions in the app
- ✅ Track completion status for engagement metrics

---

## Prerequisites

Before starting, ensure you have:

- [ ] **Supabase CLI installed**
  ```bash
  brew install supabase/tap/supabase
  supabase --version
  ```

- [ ] **Supabase project created**
  - Go to https://supabase.com/dashboard
  - Create or open your withMemento project

- [ ] **Project linked locally**
  ```bash
  supabase login
  supabase link --project-ref YOUR_PROJECT_REF
  ```
  (Find PROJECT_REF in: Dashboard → Settings → General → Reference ID)

- [ ] **At least 3 test journal entries** in your database

---

## Part 1: Deploy Backend (15 minutes)

### Step 1: Run Deployment Script

```bash
# Navigate to project root
cd /Users/sebastianmendo/Swift-projects/withMemento

# Run automated deployment
bash DEPLOY_WEEKLY_QUESTIONS.sh
```

This script will:
1. ✅ Verify Supabase CLI is installed
2. ✅ Check project is linked
3. ✅ Run database migration (creates follow_up_questions table)
4. ✅ Deploy generate-follow-up edge function
5. ✅ Deploy weekly-question-generator cron function

**Expected output:**
```
🚀 Deploying Continuous Weekly Question Generation System
==========================================================

Step 1/5: Checking Prerequisites
-----------------------------------
✓ Supabase CLI installed
✓ Logged in to Supabase
✓ Project linked

Step 2/5: Running Database Migration
---------------------------------------
✓ Migration complete

Step 3/5: Deploying generate-follow-up Function
--------------------------------------------------
✓ Function deployed

Step 4/5: Deploying weekly-question-generator Cron
----------------------------------------------------
✓ Cron function deployed

Step 5/5: Manual Testing
------------------------
⚠️  Next steps (manual):
...
```

---

### Step 2: Get Your JWT Token

You need a JWT token to test the functions.

**Method 1: From Xcode (Recommended)**
1. Open your app in Xcode
2. Run the app and sign in
3. Add this line after authentication in any view:
   ```swift
   print("JWT:", supabaseService.client.auth.session?.accessToken ?? "none")
   ```
4. Check Xcode console for the token
5. Copy the token (it's a long string starting with `eyJ...`)

**Method 2: From Supabase Dashboard**
1. Go to Dashboard → Authentication → Users
2. Click on your test user
3. Scroll to "User JWT"
4. Click "Generate JWT" and copy

---

### Step 3: Test the Functions

```bash
# Set your JWT token
export JWT_TOKEN="paste_your_token_here"

# Run test script
bash TEST_QUESTIONS.sh
```

**Expected output:**
```
🧪 Testing Weekly Question Generation System
==============================================

Test 1: Manual Question Generation
------------------------------------
✓ Success! (HTTP 200)

Response:
{
  "questions": [
    {
      "text": "What strategies help you manage stress effectively?",
      "score": 0.4523
    },
    ...
  ],
  "metadata": {
    "entriesAnalyzed": 5,
    "lookbackDays": 14,
    "savedToDatabase": true
  }
}

Generated 5 questions
```

---

### Step 4: Verify Database Storage

1. Go to: https://supabase.com/dashboard
2. Navigate to: **Table Editor** → **follow_up_questions**
3. You should see your generated questions:
   - `question_text`: The question
   - `relevance_score`: TF-IDF similarity score
   - `week_number`: Current week
   - `is_completed`: false (initially)

**Or run this SQL query:**
```sql
SELECT
  question_text,
  relevance_score,
  week_number,
  year,
  is_completed,
  generated_at
FROM follow_up_questions
WHERE user_id = auth.uid()
ORDER BY relevance_score DESC;
```

---

### Step 5: Set Up Automatic Cron Schedule

1. Go to: https://supabase.com/dashboard
2. Navigate to: **Edge Functions** → **weekly-question-generator**
3. Click the **Settings** tab
4. Find **Cron Jobs** section
5. Click **Enable Cron**
6. Enter schedule: `0 21 * * 0`
   - This means: **Every Sunday at 9:00 PM UTC**
   - Adjust if needed (see cron syntax below)
7. Click **Save**

**Cron Schedule Examples:**
- `0 21 * * 0` = Every Sunday 9 PM UTC
- `0 9 * * 1` = Every Monday 9 AM UTC
- `0 20 * * 3` = Every Wednesday 8 PM UTC
- `0 0 * * *` = Every day at midnight

**Convert UTC to your timezone:**
- 9 PM UTC = 2 PM PST / 5 PM EST

---

### Step 6: (Optional) Set Cron Secret for Security

1. In **weekly-question-generator** → **Secrets** tab
2. Click **Add Secret**
3. Key: `CRON_SECRET`
4. Value: Generate a random string:
   ```bash
   openssl rand -hex 32
   ```
5. Click **Save**

Now only requests with this secret can trigger the cron job.

---

## Part 2: Swift App Integration (30 minutes)

### Step 7: Add New Files to Xcode Project

Add these 3 new files to your Xcode project:

1. **withMemento/Models/GeneratedFollowUpQuestion.swift** ✅ Created
2. **withMemento/Services/SupabaseService+FollowUpQuestions.swift** ✅ Created
3. **withMemento/ViewModels/GeneratedQuestionsViewModel.swift** ✅ Created

**How to add:**
1. In Xcode: Right-click project navigator
2. Select "Add Files to withMemento"
3. Navigate to each file location
4. Check "Copy items if needed"
5. Click "Add"

---

### Step 8: Update JournalView

Now update `JournalView.swift` to fetch and display AI-generated questions.

**Option A: Replace Existing Follow-Up Section**

If you want to completely replace the hardcoded questions with AI-generated ones:

```swift
import SwiftUI

struct JournalView: View {
    @StateObject private var entryViewModel: EntryViewModel
    @StateObject private var generatedQuestionsViewModel = GeneratedQuestionsViewModel()

    // ... existing code ...

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ... existing entry list ...

                // REPLACE THIS SECTION
                // Old hardcoded questions:
                // if !entryViewModel.allFollowUpQuestions.isEmpty { ... }

                // NEW: AI-Generated Questions
                if !generatedQuestionsViewModel.currentWeekQuestions.isEmpty {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Follow-up Questions")
                                .font(.custom(Typography.title2))
                                .foregroundStyle(theme.foreground)

                            Spacer()

                            // Refresh button
                            Button(action: {
                                Task {
                                    await generatedQuestionsViewModel.refreshQuestions()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(theme.mutedForeground)
                            }
                            .disabled(generatedQuestionsViewModel.isRefreshing)
                        }

                        // Show "new questions" banner
                        if generatedQuestionsViewModel.showNewQuestionsNotification {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("\(generatedQuestionsViewModel.currentWeekQuestions.count) new questions this week!")
                                    .font(.custom(Typography.caption))
                                Spacer()
                                Button("Dismiss") {
                                    generatedQuestionsViewModel.dismissNotification()
                                }
                                .font(.custom(Typography.caption))
                            }
                            .foregroundStyle(theme.primary)
                            .padding(12)
                            .background(theme.primary.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Question cards
                        ForEach(generatedQuestionsViewModel.currentWeekQuestions) { question in
                            FollowUpCard(
                                question: question.questionText,
                                isCompleted: question.isCompleted
                            ) {
                                // When user taps to answer
                                onNavigateToEntry(.followUp(question.questionText))
                            }
                        }

                        // Show loading state
                        if generatedQuestionsViewModel.isLoading {
                            ProgressView()
                                .padding()
                        }

                        // Show error if any
                        if let error = generatedQuestionsViewModel.error {
                            Text(error)
                                .font(.custom(Typography.caption))
                                .foregroundStyle(.red)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task {
            // Fetch questions when view appears
            await generatedQuestionsViewModel.fetchQuestions()
        }
    }
}
```

**Option B: Show Both (AI-Generated + Manual)**

Keep both hardcoded questions and AI-generated ones:

```swift
// Show AI-generated questions
if !generatedQuestionsViewModel.currentWeekQuestions.isEmpty {
    // ... AI questions section (code from Option A) ...
}

// Keep original hardcoded questions
if !entryViewModel.allFollowUpQuestions.isEmpty {
    // ... existing hardcoded questions ...
}
```

---

### Step 9: Mark Questions as Completed

When a user answers a follow-up question, mark it as completed:

**In AddEntryView.swift** (or wherever you handle follow-up answers):

```swift
// After saving the entry
if let followUpQuestion = /* the question being answered */ {
    // Find the corresponding generated question
    if let generatedQuestion = generatedQuestionsViewModel.currentWeekQuestions.first(
        where: { $0.questionText == followUpQuestion }
    ) {
        // Mark as completed
        await generatedQuestionsViewModel.completeQuestion(
            generatedQuestion,
            withEntryId: savedEntry.id
        )
    }
}
```

---

## Part 3: Testing (15 minutes)

### Test 1: Manual Generation

1. Open app in Xcode
2. Navigate to Journal tab
3. Tap the refresh button (↻)
4. Should see loading indicator
5. New questions appear
6. Check Supabase database for new rows

---

### Test 2: Automatic Weekly Generation

**Option A: Wait for Sunday 9 PM**
- Just wait for the scheduled time
- Check logs: `supabase functions logs weekly-question-generator --tail`
- Open app Monday morning to see new questions

**Option B: Test Immediately (Manual Trigger)**
```bash
# Trigger cron job manually
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/weekly-question-generator

# Check logs
supabase functions logs weekly-question-generator --tail
```

---

### Test 3: Completion Tracking

1. In the app, tap a follow-up question
2. Write a journal entry answering it
3. Save the entry
4. Go back to Journal tab
5. Question should show checkmark (completed state)
6. Verify in database:
   ```sql
   SELECT * FROM follow_up_questions
   WHERE is_completed = true
   AND user_id = auth.uid();
   ```

---

### Test 4: Sliding Window (Relevance)

Test that questions stay relevant to recent entries:

**Week 1:**
1. Write 3 entries about "work stress"
2. Generate questions → Should get stress/work questions

**Week 2:**
3. Write 5 entries about "gratitude" and "family"
4. Wait for Sunday 9 PM (or trigger manually)
5. Check new questions → Should shift toward gratitude/relationships

---

## Part 4: Monitoring (Ongoing)

### View Function Logs

```bash
# Real-time logs for question generation
supabase functions logs generate-follow-up --tail

# Real-time logs for cron job
supabase functions logs weekly-question-generator --tail

# Search for errors
supabase functions logs generate-follow-up | grep "ERROR"
```

---

### Check Engagement Metrics

```sql
-- Questions answered per week
SELECT
  week_number,
  year,
  COUNT(*) FILTER (WHERE is_completed = true) as completed,
  COUNT(*) as total,
  ROUND(COUNT(*) FILTER (WHERE is_completed = true)::numeric / COUNT(*) * 100, 2) as completion_rate
FROM follow_up_questions
GROUP BY week_number, year
ORDER BY year DESC, week_number DESC
LIMIT 10;

-- Your personal stats
SELECT
  COUNT(*) as total_questions,
  COUNT(*) FILTER (WHERE is_completed = true) as completed,
  ROUND(AVG(relevance_score), 3) as avg_relevance
FROM follow_up_questions
WHERE user_id = auth.uid();

-- Most recent questions
SELECT
  question_text,
  relevance_score,
  is_completed,
  TO_CHAR(generated_at, 'Mon DD, YYYY') as generated
FROM follow_up_questions
WHERE user_id = auth.uid()
ORDER BY generated_at DESC
LIMIT 10;
```

---

## Troubleshooting

### "No meaningful tokens found"
**Cause:** Entries only contain common words (stop words)
**Fix:** Write longer, more detailed journal entries

---

### "Need at least 3 journal entries"
**Cause:** User has < 3 entries in last 14 days
**Fix:** Write more entries, or adjust lookbackDays to a larger window

---

### Questions not appearing in app
**Causes:**
1. Network error
2. Questions not saved to database
3. JWT token expired

**Debug:**
```swift
// Add logging in fetchQuestions()
print("Fetching questions for week:", getCurrentWeekNumber())
print("Fetched:", questions.count, "questions")
```

---

### Cron job not running
**Check:**
1. Is cron enabled in Supabase Dashboard?
2. Is the schedule correct?
3. Check logs for errors:
   ```bash
   supabase functions logs weekly-question-generator
   ```

---

## Configuration

### Change Lookback Window

**Default:** 14 days (2 weeks)

**To change:**

In `weekly-question-generator/index.ts`, modify:
```typescript
body: JSON.stringify({
  lookbackDays: 21, // Change to 3 weeks
  saveToDatabase: true
})
```

Redeploy:
```bash
supabase functions deploy weekly-question-generator
```

---

### Change Cron Schedule

1. Go to Supabase Dashboard → Edge Functions → weekly-question-generator → Settings
2. Change cron expression
3. Click Save

---

### Adjust Question Count

**Default:** 5 questions per week

**To change:**

In `generate-follow-up/index.ts`, modify line 176:
```typescript
if (selectedQuestions.length >= 7) break; // Change 5 to 7
```

Redeploy:
```bash
supabase functions deploy generate-follow-up
```

---

## Next Steps

Once everything is working:

1. **Add Push Notifications**
   - Send notification Monday morning: "New questions available!"
   - Remind users mid-week if incomplete

2. **Analytics Dashboard**
   - Track which themes are most common
   - Show user their engagement streak

3. **Expand Question Bank**
   - Currently: 15 questions
   - Goal: 100+ questions for more variety

4. **Smart Scheduling**
   - Generate when user is most active
   - Personalized timing per user

---

## Summary Checklist

Backend Deployment:
- [ ] Database migration run
- [ ] `generate-follow-up` function deployed
- [ ] `weekly-question-generator` function deployed
- [ ] Cron schedule enabled (Sunday 9 PM)
- [ ] Manual test successful
- [ ] Questions visible in database

Swift Integration:
- [ ] `GeneratedFollowUpQuestion.swift` added to Xcode
- [ ] `SupabaseService+FollowUpQuestions.swift` added to Xcode
- [ ] `GeneratedQuestionsViewModel.swift` added to Xcode
- [ ] JournalView updated to fetch questions
- [ ] Refresh button works
- [ ] Completion tracking implemented

Testing:
- [ ] Manual generation works
- [ ] Questions appear in app
- [ ] Completion status updates
- [ ] Cron job tested (manual trigger)
- [ ] Logs show no errors

---

## Support

**View logs:**
```bash
supabase functions logs generate-follow-up --tail
supabase functions logs weekly-question-generator --tail
```

**Check database:**
```sql
SELECT * FROM follow_up_questions WHERE user_id = auth.uid();
```

**Re-deploy if needed:**
```bash
bash DEPLOY_WEEKLY_QUESTIONS.sh
```

---

**You're all set! 🎉**

Every Sunday at 9 PM, your users will automatically get 5 fresh, personalized follow-up questions based on their recent journal entries.
