# Continuous Weekly Question Generation - Implementation Guide

## Overview

This system automatically generates personalized follow-up questions for users **every week**, keeping them engaged with fresh, relevant questions based on their recent journal entries.

---

## How It Works

### User Journey

**Week 1:**
- User writes 3+ journal entries about work stress
- System generates 5 follow-up questions about stress management, boundaries
- User answers 2 questions

**Week 2:**
- User writes 5 more entries (mix of stress + gratitude)
- **Every Sunday 9 PM:** Cron job runs automatically
- System analyzes last 14 days of entries (8 total)
- Generates NEW 5 questions based on recent themes
- Old questions remain visible (marked as "Week 1")

**Week 3:**
- User writes 2 entries about relationships
- **Sunday 9 PM:** Cron job runs again
- System analyzes last 14 days (7 entries: stress + relationships)
- Generates NEW 5 questions focused on relationships
- Questions stay relevant to current life events

### Key Features

1. **Sliding Window Analysis**
   - Always analyzes entries from last 14 days
   - Older entries naturally phase out
   - Questions stay relevant to recent life events

2. **Weekly Automatic Generation**
   - Supabase Cron runs every Sunday at 9 PM UTC
   - Processes all active users (wrote ≥1 entry in last 30 days)
   - Saves questions to database with week number

3. **Completion Tracking**
   - Each question has completion status
   - Links to the journal entry that answered it
   - Can track engagement metrics

4. **Theme Diversity**
   - Questions cover different themes each week
   - Prevents repetitive questions
   - Adapts to changing journal topics

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  1. USER WRITES JOURNAL ENTRIES                             │
│     (Throughout the week)                                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  2. CRON JOB TRIGGERS (Every Sunday 9 PM)                   │
│     → weekly-question-generator edge function                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  3. FOR EACH ACTIVE USER:                                   │
│     → Call generate-follow-up function                       │
│     → Analyze entries from last 14 days                      │
│     → Generate 5 personalized questions                      │
│     → Save to follow_up_questions table                      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  4. USER OPENS APP                                          │
│     → Fetch questions from database                          │
│     → Display current week's questions                       │
│     → Show "3 new questions available!" notification         │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Phase 1: Database Setup

#### Step 1.1: Run Migration

```bash
# Navigate to project root
cd /Users/sebastianmendo/Swift-projects/withMemento

# Link to Supabase project (if not already linked)
supabase link --project-ref YOUR_PROJECT_REF

# Apply migration
supabase db push
```

This creates the `follow_up_questions` table with:
- Question text and relevance score
- Week number and year tracking
- Completion status
- User association with RLS policies

#### Step 1.2: Verify Table

Go to Supabase Dashboard → SQL Editor and run:

```sql
-- Check table exists
SELECT * FROM follow_up_questions LIMIT 1;

-- Test helper function
SELECT * FROM get_current_week_questions('YOUR_USER_ID');
```

---

### Phase 2: Deploy Edge Functions

#### Step 2.1: Deploy generate-follow-up Function

```bash
# Deploy with updated sliding window logic
supabase functions deploy generate-follow-up
```

**Test it works:**

```bash
# Test with 14-day lookback and database save
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/generate-follow-up \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "lookbackDays": 14,
    "saveToDatabase": true
  }'
```

Expected response:
```json
{
  "questions": [...],
  "metadata": {
    "entriesAnalyzed": 5,
    "lookbackDays": 14,
    "savedToDatabase": true
  }
}
```

**Verify in database:**
```sql
SELECT * FROM follow_up_questions WHERE user_id = 'YOUR_USER_ID';
```

#### Step 2.2: Deploy weekly-question-generator Cron Function

```bash
supabase functions deploy weekly-question-generator
```

---

### Phase 3: Set Up Cron Schedule

#### Step 3.1: Enable Cron in Supabase Dashboard

1. Go to **Supabase Dashboard** → **Edge Functions**
2. Click **weekly-question-generator**
3. Go to **Settings** tab
4. Click **Enable Cron**
5. Set schedule: `0 21 * * 0` (Every Sunday at 9 PM UTC)
6. Click **Save**

#### Step 3.2: Set Cron Secret (Optional but Recommended)

1. In Supabase Dashboard → **Edge Functions** → **weekly-question-generator**
2. Go to **Secrets** tab
3. Add secret:
   - Key: `CRON_SECRET`
   - Value: Generate random string (e.g., `openssl rand -hex 32`)
4. Click **Save**

#### Step 3.3: Test Cron Manually

```bash
# Trigger manually (don't wait for Sunday)
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/weekly-question-generator \
  -H "x-cron-secret: YOUR_CRON_SECRET"
```

Expected response:
```json
{
  "message": "Weekly question generation complete",
  "timestamp": "2025-01-18T21:00:00.000Z",
  "results": {
    "total": 5,
    "successful": 5,
    "failed": 0,
    "errors": []
  }
}
```

---

### Phase 4: Swift App Integration

#### Step 4.1: Create Swift Models

Create `withMemento/Models/FollowUpQuestion.swift`:

```swift
import Foundation

struct FollowUpQuestion: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let questionText: String
    let relevanceScore: Double
    let generatedAt: Date
    let weekNumber: Int
    let year: Int
    let isCompleted: Bool
    let completedAt: Date?
    let entryId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case questionText = "question_text"
        case relevanceScore = "relevance_score"
        case generatedAt = "generated_at"
        case weekNumber = "week_number"
        case year
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case entryId = "entry_id"
    }
}

struct GeneratedQuestionsResponse: Codable {
    let questions: [QuestionWithScore]
    let metadata: QuestionMetadata

    struct QuestionWithScore: Codable {
        let text: String
        let score: Double
    }

    struct QuestionMetadata: Codable {
        let entriesAnalyzed: Int
        let generatedAt: String
        let themesCount: Int
        let lookbackDays: Int
        let savedToDatabase: Bool
    }
}
```

#### Step 4.2: Add SupabaseService Methods

Add to `withMemento/Services/SupabaseService.swift`:

```swift
// MARK: - Follow-Up Questions

/// Fetch current week's questions from database
func fetchCurrentWeekQuestions() async throws -> [FollowUpQuestion] {
    let response = try await client
        .from("follow_up_questions")
        .select()
        .eq("user_id", try getCurrentUserId())
        .eq("week_number", getCurrentWeekNumber())
        .eq("year", getCurrentYear())
        .order("relevance_score", ascending: false)
        .execute()

    return try response.value.decode([FollowUpQuestion].self)
}

/// Generate new questions on-demand (manual refresh)
func generateFollowUpQuestions(lookbackDays: Int = 14) async throws -> GeneratedQuestionsResponse {
    struct RequestBody: Encodable {
        let lookbackDays: Int
        let saveToDatabase: Bool
    }

    let body = RequestBody(lookbackDays: lookbackDays, saveToDatabase: true)

    let response = try await client.functions.invoke(
        "generate-follow-up",
        options: FunctionInvokeOptions(
            body: body
        )
    )

    return try response.value.decode(GeneratedQuestionsResponse.self)
}

/// Mark question as completed
func completeFollowUpQuestion(questionId: UUID, entryId: UUID) async throws {
    try await client.rpc(
        "complete_follow_up_question",
        params: [
            "p_question_id": questionId.uuidString,
            "p_entry_id": entryId.uuidString
        ]
    ).execute()
}

// MARK: - Helper Functions

private func getCurrentWeekNumber() -> Int {
    let calendar = Calendar.current
    let weekOfYear = calendar.component(.weekOfYear, from: Date())
    return weekOfYear
}

private func getCurrentYear() -> Int {
    let calendar = Calendar.current
    return calendar.component(.year, from: Date())
}

private func getCurrentUserId() throws -> String {
    guard let userId = client.auth.currentUser?.id.uuidString else {
        throw SupabaseError.notAuthenticated
    }
    return userId
}
```

#### Step 4.3: Create ViewModel

Create `withMemento/ViewModels/FollowUpQuestionsViewModel.swift`:

```swift
import Foundation

@MainActor
class FollowUpQuestionsViewModel: ObservableObject {
    @Published var currentWeekQuestions: [FollowUpQuestion] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showNewQuestionsNotification = false

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    /// Fetch questions for current week
    func fetchQuestions() async {
        isLoading = true
        error = nil

        do {
            let questions = try await supabaseService.fetchCurrentWeekQuestions()
            currentWeekQuestions = questions

            // Check if there are new questions
            if !questions.isEmpty && !hasSeenCurrentWeek() {
                showNewQuestionsNotification = true
                markWeekAsSeen()
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Manually refresh questions (user taps refresh button)
    func refreshQuestions() async {
        isLoading = true
        error = nil

        do {
            _ = try await supabaseService.generateFollowUpQuestions(lookbackDays: 14)

            // Fetch the newly generated questions
            await fetchQuestions()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Mark question as completed
    func completeQuestion(_ question: FollowUpQuestion, withEntryId entryId: UUID) async {
        do {
            try await supabaseService.completeFollowUpQuestion(
                questionId: question.id,
                entryId: entryId
            )

            // Refresh questions to update UI
            await fetchQuestions()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Notification Tracking

    private func hasSeenCurrentWeek() -> Bool {
        let key = "seenWeek_\(getCurrentYear())_\(getCurrentWeekNumber())"
        return UserDefaults.standard.bool(forKey: key)
    }

    private func markWeekAsSeen() {
        let key = "seenWeek_\(getCurrentYear())_\(getCurrentWeekNumber())"
        UserDefaults.standard.set(true, forKey: key)
    }

    private func getCurrentWeekNumber() -> Int {
        Calendar.current.component(.weekOfYear, from: Date())
    }

    private func getCurrentYear() -> Int {
        Calendar.current.component(.year, from: Date())
    }
}
```

#### Step 4.4: Update JournalView

Update `withMemento/Views/Journal/JournalView.swift`:

```swift
@StateObject private var followUpViewModel = FollowUpQuestionsViewModel()

var body: some View {
    // ... existing code

    // Replace hardcoded questions with database questions
    if !followUpViewModel.currentWeekQuestions.isEmpty {
        VStack(spacing: 16) {
            HStack {
                Text("Follow-up Questions")
                    .font(.custom(Typography.title2))
                    .foregroundStyle(theme.foreground)

                Spacer()

                // Show refresh button
                Button(action: {
                    Task {
                        await followUpViewModel.refreshQuestions()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(theme.mutedForeground)
                }
            }

            ForEach(followUpViewModel.currentWeekQuestions) { question in
                FollowUpCard(
                    question: question.questionText,
                    isCompleted: question.isCompleted
                ) {
                    onNavigateToEntry(.followUp(question.questionText))
                }
            }

            // Show "new questions" banner
            if followUpViewModel.showNewQuestionsNotification {
                HStack {
                    Image(systemName: "sparkles")
                    Text("\(followUpViewModel.currentWeekQuestions.count) new questions this week!")
                        .font(.custom(Typography.caption))
                }
                .foregroundStyle(theme.primary)
                .padding(12)
                .background(theme.primary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
    }
}

.task {
    await followUpViewModel.fetchQuestions()
}
```

---

## Testing the Complete Flow

### Test 1: Manual Generation

```bash
# 1. Add test entries
# Go to Supabase Dashboard → Table Editor → journal_entries
# Add 3-5 entries with different dates (within last 14 days)

# 2. Call generate function manually
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/generate-follow-up \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{"lookbackDays": 14, "saveToDatabase": true}'

# 3. Verify in database
SELECT * FROM follow_up_questions WHERE user_id = 'YOUR_USER_ID';

# 4. Open Swift app → Should show questions
```

### Test 2: Cron Job

```bash
# 1. Trigger cron manually
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/weekly-question-generator \
  -H "x-cron-secret: YOUR_SECRET"

# 2. Check logs
supabase functions logs weekly-question-generator --tail

# 3. Verify questions generated for all users
SELECT user_id, COUNT(*)
FROM follow_up_questions
WHERE week_number = EXTRACT(WEEK FROM NOW())
GROUP BY user_id;
```

### Test 3: Sliding Window

```bash
# 1. Add entries with different dates
INSERT INTO journal_entries (user_id, text, created_at) VALUES
  ('YOUR_ID', 'Entry from 20 days ago', NOW() - INTERVAL '20 days'),
  ('YOUR_ID', 'Entry from 10 days ago', NOW() - INTERVAL '10 days'),
  ('YOUR_ID', 'Entry from 5 days ago', NOW() - INTERVAL '5 days'),
  ('YOUR_ID', 'Entry from today', NOW());

# 2. Generate with lookbackDays=14
# Should only analyze last 3 entries (not the 20-day old one)

# 3. Verify in logs
supabase functions logs generate-follow-up --tail
# Look for: "📊 Analyzing X entries" (should be 3, not 4)
```

### Test 4: Swift App End-to-End

1. Open app in Xcode
2. Navigate to Journal tab
3. Should see current week's questions
4. Tap refresh → New questions generated
5. Answer a question → Status updates to completed
6. Reopen app next week → New questions appear

---

## Configuration Options

### Adjust Lookback Window

In `weekly-question-generator/index.ts`, change:

```typescript
body: JSON.stringify({
  lookbackDays: 21, // Change to 3 weeks instead of 2
  saveToDatabase: true
})
```

### Change Cron Schedule

In Supabase Dashboard → Edge Functions → Cron Settings:

- `0 21 * * 0` = Every Sunday 9 PM
- `0 21 * * 3` = Every Wednesday 9 PM
- `0 9 * * 1` = Every Monday 9 AM
- `0 0 * * *` = Every day at midnight

### Adjust Active User Definition

In `weekly-question-generator/index.ts`, change:

```typescript
thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 7); // Only users active in last 7 days
```

---

## Monitoring & Analytics

### Track Engagement Metrics

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
ORDER BY year DESC, week_number DESC;

-- Top users by engagement
SELECT
  user_id,
  COUNT(*) FILTER (WHERE is_completed = true) as questions_answered,
  COUNT(*) as questions_generated
FROM follow_up_questions
GROUP BY user_id
ORDER BY questions_answered DESC
LIMIT 10;

-- Average relevance scores
SELECT
  AVG(relevance_score) as avg_score,
  MIN(relevance_score) as min_score,
  MAX(relevance_score) as max_score
FROM follow_up_questions
WHERE is_completed = true; -- Only completed questions
```

### Monitor Cron Job Performance

```bash
# View cron logs
supabase functions logs weekly-question-generator --tail

# Check for errors
supabase functions logs weekly-question-generator | grep "ERROR"

# Count successful runs
supabase functions logs weekly-question-generator | grep "successful" | wc -l
```

---

## Summary

✅ **What You've Built:**
- Sliding window analysis (always analyzes last 14 days)
- Weekly automatic generation via cron job
- Database storage with completion tracking
- Swift app integration for real-time updates

✅ **User Experience:**
- Fresh questions every week
- Questions stay relevant to recent entries
- Completion tracking
- Optional manual refresh

✅ **Engagement Loop:**
1. User writes entries throughout week
2. Sunday 9 PM: New questions generated automatically
3. Monday morning: User opens app → "3 new questions!"
4. User answers questions → Writes more entries
5. Repeat next week

---

## Next Steps

1. **Deploy Functions:**
   ```bash
   supabase functions deploy generate-follow-up
   supabase functions deploy weekly-question-generator
   ```

2. **Run Migration:**
   ```bash
   supabase db push
   ```

3. **Set Up Cron:**
   - Supabase Dashboard → Edge Functions → Enable Cron

4. **Test Manually:**
   - Trigger cron manually
   - Verify questions in database
   - Open Swift app

5. **Monitor First Week:**
   - Check logs every day
   - Verify questions generated Sunday night
   - Track user engagement

6. **Optional: Add Push Notifications:**
   - Send notification Monday morning: "New questions available!"
   - Remind users mid-week if questions incomplete

Let me know when you're ready to deploy!
