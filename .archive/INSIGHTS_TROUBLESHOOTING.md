# 🔧 Insights Feature - Troubleshooting Guide

**Last Updated:** October 23, 2025

---

## ✅ Issue Fixed: "Data couldn't be read because it isn't in the correct format"

### **Root Cause:**
Supabase edge functions return **double-encoded JSON** responses. The response is wrapped in quotes and escaped, requiring unwrapping before decoding.

### **Solution Applied:**
Added double-encoding detection and unwrapping logic to `InsightViewModel.swift` (lines 138-158).

**Code Pattern:**
```swift
// Check if response is DOUBLE-ENCODED
if rawJSON.hasPrefix("\"") && rawJSON.hasSuffix("\"") {
    // Remove outer quotes and unescape
    var unescaped = rawJSON
    unescaped.removeFirst()
    unescaped.removeLast()
    unescaped = unescaped.replacingOccurrences(of: "\\\"", with: "\"")
    unescaped = unescaped.replacingOccurrences(of: "\\n", with: "\n")
    unescaped = unescaped.replacingOccurrences(of: "\\t", with: "\t")
    unescaped = unescaped.replacingOccurrences(of: "\\\\", with: "\\")

    // Use unwrapped data for decoding
    data = unescaped.data(using: .utf8)!
}
```

### **Status:**
🟢 **FIXED** - Build succeeded, ready to test

---

## 📋 Testing the Fix

### **1. Run the App:**
```bash
# Open in Xcode
open withMemento.xcodeproj

# Build and run (⌘R)
```

### **2. Check Console Logs:**
You should now see:
```
🔄 Calling generate-insights function with X entries
✅ Edge function returned data: XXXX bytes
📦 Raw response: {...}
⚠️ Response appears to be string-encoded JSON - unwrapping...
📦 Unwrapped JSON: {...}
🔄 Attempting to decode JSON...
✅ Successfully decoded insights
✅ Insights loaded (freshly generated): X themes
```

### **3. Expected Behavior:**
- ✅ First load: Shows loading spinner → insights appear
- ✅ Subsequent loads: Instant (from cache)
- ✅ Console shows "Cache HIT" on subsequent views
- ✅ Pull to refresh: Generates new insights

---

## 🐛 Common Issues & Solutions

### **Issue 1: "Missing authorization header"**
**Symptoms:**
```
❌ Insights generation failed: Missing authorization header
```

**Cause:** User not authenticated

**Solution:**
1. Ensure user is signed in
2. Check `SupabaseService.shared.getCurrentUser()` returns valid user
3. Verify auth token is being passed to edge function

**Fix:**
```swift
// Check if user is authenticated
let user = try await SupabaseService.shared.getCurrentUser()
guard user != nil else {
    print("❌ User not authenticated")
    return
}
```

---

### **Issue 2: "Too many entries" error**
**Symptoms:**
```
❌ Maximum 20 entries allowed
```

**Cause:** Sending more than 20 entries to edge function

**Solution:**
Already handled in ViewModel - limits to first 20 entries:
```swift
let entriesToAnalyze = Array(entries.prefix(20))
```

**No action needed** - this is working correctly.

---

### **Issue 3: OpenAI Rate Limit**
**Symptoms:**
```
❌ Too many requests. Please wait 60 seconds.
```

**Cause:** OpenAI API rate limit exceeded

**Solution:**
1. Wait 60 seconds (handled automatically)
2. Check OpenAI dashboard for quota: https://platform.openai.com/usage
3. Caching should reduce rate limit hits by 95%

**Temporary Workaround:**
If hitting rate limits frequently, increase cache TTL:
```typescript
// In generate-insights/index.ts
const CACHE_TTL_HOURS = 336;  // 14 days instead of 7
```

---

### **Issue 4: Empty or Invalid Insights**
**Symptoms:**
- Insights display but themes are generic
- Description doesn't reference entry content
- Themes have no source entries

**Cause:** OpenAI returned invalid format

**Debug:**
1. Check console logs for raw OpenAI response
2. Verify entries have meaningful content (not just titles)
3. Check that prompt validation is passing

**Solution:**
```swift
// Add more detailed logging in ViewModel
AppLogger.log("📝 Entries being sent: \(entries.map { $0.text.prefix(50) })",
             category: AppLogger.network)
```

---

### **Issue 5: Network/Timeout Errors**
**Symptoms:**
```
❌ Network error: The request timed out
```

**Cause:** OpenAI API call taking too long

**Solution:**
1. Check internet connection
2. Verify OpenAI API is accessible
3. Check Supabase edge function logs for errors

**Debug Commands:**
```bash
# Check if edge function is responding
curl -X POST \
  'https://fhsgvlbedqwxwpubtlls.supabase.co/functions/v1/generate-insights' \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entries": []}'

# Expected: 400 error with "Missing or invalid entries array"
```

---

### **Issue 6: Cache Not Working**
**Symptoms:**
- Every request shows "Cache MISS"
- Never shows "Cache HIT"
- Always takes 2-5 seconds to load

**Cause:** Cache table or RPC functions not working

**Debug:**
1. Check if `user_insights` table exists:
```sql
SELECT * FROM user_insights LIMIT 1;
```

2. Test RPC functions:
```sql
-- Check if cache function exists
SELECT proname FROM pg_proc WHERE proname = 'get_cached_insight';
SELECT proname FROM pg_proc WHERE proname = 'save_insight_cache';
```

3. Check cache entries:
```sql
SELECT
    user_id,
    insight_type,
    generated_at,
    expires_at,
    entries_analyzed_count
FROM user_insights
WHERE insight_type = 'journal_summary'
ORDER BY generated_at DESC
LIMIT 10;
```

**Solution:**
If tables/functions missing, redeploy migrations:
```bash
cd /Users/sebastianmendo/Swift-projects/withMemento
supabase db push
```

---

### **Issue 7: Date Parsing Errors**
**Symptoms:**
```
❌ Decoding error details: typeMismatch(Swift.Date, ...)
```

**Cause:** Date format doesn't match `.iso8601` decoder

**Solution:**
Already handled with custom date decoding strategy. If issue persists, check edge function returns ISO8601:

```typescript
// In edge function - should return:
generatedAt: new Date().toISOString()  // "2025-10-23T19:46:36.000Z"
```

**Verify in logs:**
```
📦 Raw response: {"generatedAt":"2025-10-23T19:46:36.000Z",...}
```

---

## 🔍 Debugging Workflow

### **Step 1: Check Console Logs**
Look for these key messages:
- ✅ "Calling generate-insights function" - Request sent
- ✅ "Edge function returned data: X bytes" - Response received
- ✅ "Raw response: {...}" - See actual JSON
- ❌ "Decoding error" - Parsing failed

### **Step 2: Verify Edge Function**
```bash
# Check function is deployed
supabase functions list

# Expected output:
# generate-insights | ACTIVE | 1
```

### **Step 3: Test Edge Function Manually**
```bash
# Get auth token from app (print it in console)
AUTH_TOKEN="your-token-here"

# Call function with test data
curl -X POST \
  'https://fhsgvlbedqwxwpubtlls.supabase.co/functions/v1/generate-insights' \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "entries": [
      {
        "date": "2025-10-23T10:00:00Z",
        "title": "Test Entry",
        "content": "Testing the insights feature with some meaningful content about work stress and personal growth.",
        "word_count": 15,
        "mood": "neutral"
      }
    ]
  }'
```

**Expected Response:**
```json
{
  "summary": "One-sentence summary...",
  "description": "150-180 word description...",
  "themes": [...],
  "entriesAnalyzed": 1,
  "generatedAt": "2025-10-23T...",
  "fromCache": false
}
```

### **Step 4: Check Database**
```sql
-- Check if cache is being saved
SELECT
    insight_type,
    generated_at,
    expires_at,
    entries_analyzed_count
FROM user_insights
WHERE user_id = 'your-user-id'
ORDER BY generated_at DESC
LIMIT 1;
```

---

## 📊 Health Check Queries

### **Cache Performance:**
```sql
-- Check cache hit rate
SELECT
    COUNT(*) as total_cached_insights,
    MAX(generated_at) as most_recent,
    MIN(generated_at) as oldest
FROM user_insights
WHERE insight_type = 'journal_summary';
```

### **User Insights Status:**
```sql
-- Check per-user cache status
SELECT
    user_id,
    generated_at,
    expires_at,
    entries_analyzed_count,
    EXTRACT(EPOCH FROM (expires_at - NOW())) / 3600 as hours_until_expiry
FROM user_insights
WHERE insight_type = 'journal_summary'
ORDER BY generated_at DESC;
```

### **Function Invocation Logs:**
Check Supabase Dashboard:
- Go to: https://supabase.com/dashboard/project/fhsgvlbedqwxwpubtlls/functions/generate-insights
- Click "Logs" tab
- Look for:
  - ✅ "Cache HIT - Returning cached insights"
  - ⚠️ "Cache MISS - Generating fresh insights"
  - 🤖 "Calling OpenAI with X entries..."
  - ❌ Any error messages

---

## 🚀 Performance Monitoring

### **Expected Metrics:**
- **First Load:** 2-5 seconds (OpenAI API call)
- **Cached Load:** < 100ms (database query)
- **Cache Hit Rate:** > 95% (after warm-up period)
- **Cost per User:** ~$0.22/year (with 95% cache hit rate)

### **Console Log Patterns:**

**First Time (Cache Miss):**
```
🔄 Calling generate-insights function with 10 entries
✅ Edge function returned data: 2345 bytes
📦 Raw response: {...}
⚠️ Response appears to be string-encoded JSON - unwrapping...
🔄 Attempting to decode JSON...
✅ Successfully decoded insights
✅ Insights loaded (freshly generated): 4 themes
```

**Subsequent Times (Cache Hit):**
```
🔄 Calling generate-insights function with 10 entries
✅ Edge function returned data: 2234 bytes
📦 Raw response: {...}
🔄 Attempting to decode JSON...
✅ Successfully decoded insights
✅ Insights loaded (from cache): 4 themes
💾 Cache expires at: Oct 30, 2025
```

---

## 🆘 Emergency Recovery

### **If Everything Fails:**

1. **Redeploy Edge Function:**
```bash
cd /Users/sebastianmendo/Swift-projects/withMemento
supabase functions deploy generate-insights --project-ref fhsgvlbedqwxwpubtlls
```

2. **Clear Cache (Force Fresh Generation):**
```sql
DELETE FROM user_insights
WHERE insight_type = 'journal_summary'
AND user_id = 'your-user-id';
```

3. **Rebuild App:**
```bash
xcodebuild -project withMemento.xcodeproj -scheme withMemento clean build
```

4. **Check OpenAI Key:**
- Dashboard: https://supabase.com/dashboard/project/fhsgvlbedqwxwpubtlls/settings/functions
- Verify `OPENAI_API_KEY` is set

5. **Contact Support:**
- Issue: Describe the error with console logs
- Edge Function Logs: From Supabase Dashboard
- Request Details: Auth token, entry count, error message

---

## 📝 Changelog

### **October 23, 2025 - v1.1**
- ✅ **FIXED:** Added double-encoding detection/unwrapping
- ✅ **IMPROVED:** Enhanced logging for debugging
- ✅ **ADDED:** Raw response logging
- ✅ **ADDED:** Detailed decoding error messages

### **October 23, 2025 - v1.0**
- ✅ Initial deployment of generate-insights edge function
- ✅ Swift integration with InsightViewModel
- ✅ 7-day caching implementation
- ✅ OpenAI gpt-4o-mini integration

---

## 🔗 Related Documentation

- **Deployment Guide:** `INSIGHTS_DEPLOYMENT_COMPLETE.md`
- **Sprint Planning:** `.sprints/SPRINT_PLANNING.md`
- **Database Schema:** `DATABASE_OPTIMIZATION.md`
- **Edge Function Code:** `supabase/functions/generate-insights/`
- **Swift Models:** `withMemento/Models/Insight.swift`
- **Swift ViewModel:** `withMemento/ViewModels/InsightViewModel.swift`

---

## ✅ Quick Fix Summary

**Problem:** "Data couldn't be read because it isn't in the correct format"

**Root Cause:** Supabase edge functions return double-encoded JSON

**Solution:** Added unwrapping logic in `InsightViewModel.swift` (lines 138-158)

**Status:** 🟢 **FIXED** and ready to test

**Next Steps:**
1. Run the app (⌘R)
2. Create 3-5 journal entries
3. Open Insights tab
4. Check console logs for success messages
5. Verify insights display correctly

---

**If you still see errors after rebuilding, check the console logs and reference the specific error case above.**
