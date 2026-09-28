# Sprint 1: InsightsViewModel Foundation

**Status**: 🔄 Ready to Start
**Duration**: 2-3 days
**Sprint Goal**: Create the ViewModel layer for AI insights caching

---

## 🎯 Objectives

1. Create InsightsViewModel class with caching logic
2. Implement cache checking and saving
3. Add error handling
4. Set up logging for debugging

---

## 📋 Tasks Breakdown

### Task 1.1: Create Data Models (30 mins)
**File**: `withMemento/Models/Insights.swift`

- [ ] Create `JournalInsights` struct
- [ ] Create `InsightSummary` struct
- [ ] Make both `Codable` for JSON encoding/decoding
- [ ] Add sample data for previews

**Code Template**:
```swift
struct JournalInsights: Codable {
    let summary: InsightSummary
    let themes: [String]
    let generatedAt: Date
    let entriesAnalyzed: Int
}

struct InsightSummary: Codable {
    let title: String
    let body: String
}
```

### Task 1.2: Create ViewModel Class (1 hour)
**File**: `withMemento/ViewModels/InsightsViewModel.swift`

- [ ] Create `InsightsViewModel` class
- [ ] Add `@MainActor` attribute
- [ ] Inherit from `ObservableObject`
- [ ] Add published properties: `insights`, `isLoading`, `errorMessage`
- [ ] Add reference to Supabase client

**Properties**:
```swift
@MainActor
class InsightsViewModel: ObservableObject {
    @Published var insights: JournalInsights?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseService.shared.supabase
}
```

### Task 1.3: Implement Cache Checking (2 hours)
**Function**: `getCachedInsights(userId:)`

- [ ] Create function signature
- [ ] Query `user_insights` table via RPC function
- [ ] Parse JSONB content to `JournalInsights`
- [ ] Handle missing cache (return nil)
- [ ] Add error handling
- [ ] Add console logging

**Implementation Notes**:
- Use `get_cached_insight` RPC function
- Pass `p_user_id` and `p_insight_type: "journal_summary"`
- Decode JSONB content field
- Log cache hits/misses

### Task 1.4: Implement Cache Saving (2 hours)
**Function**: `saveToCacheBackground(userId:insights:entriesCount:)`

- [ ] Create function signature
- [ ] Encode insights to JSON
- [ ] Call `save_insight_cache` RPC function
- [ ] Set 7-day TTL (168 hours)
- [ ] Add error handling
- [ ] Add console logging

**Implementation Notes**:
- Encode with `JSONEncoder` using `.iso8601` date strategy
- Convert to JSONSerialization object
- Pass to RPC function with all parameters

### Task 1.5: Implement Main Fetch Function (2 hours)
**Function**: `fetchInsights(forUserId:entries:)`

- [ ] Check cache first
- [ ] If hit: return cached insights
- [ ] If miss: generate new insights
- [ ] Handle loading states
- [ ] Handle errors gracefully

**Flow**:
```
1. Set isLoading = true
2. Try getCachedInsights()
3. If cached exists:
   - Set insights = cached
   - Check if stale → refresh in background
4. If no cache:
   - Call generateInsights()
   - Save to cache
5. Set isLoading = false
```

### Task 1.6: Implement Cache Staleness (30 mins)
**Function**: `isCacheStale(_:)`

- [ ] Check if insights older than 24 hours
- [ ] Return boolean
- [ ] Use for background refresh

**Logic**:
```swift
private func isCacheStale(_ insights: JournalInsights) -> Bool {
    let dayAgo = Date().addingTimeInterval(-86400)
    return insights.generatedAt < dayAgo
}
```

### Task 1.7: Implement Mock Generator (1 hour)
**Function**: `generateInsights(entries:)`

- [ ] Create placeholder implementation
- [ ] Return mock `JournalInsights`
- [ ] Simulate 2-second delay
- [ ] Include entry count in response

**Note**: Real AI implementation comes in Sprint 4

### Task 1.8: Add Error Handling (30 mins)
**Enum**: `InsightsError`

- [ ] Create error enum
- [ ] Add cases: `clientNotConfigured`, `noEntries`, `generationFailed`
- [ ] Implement `LocalizedError` protocol
- [ ] Add user-friendly error messages

### Task 1.9: Add Logging (30 mins)

- [ ] Add console logs for cache hits
- [ ] Add console logs for cache misses
- [ ] Add console logs for saves
- [ ] Add error logs
- [ ] Use emoji for easy scanning (✅ ⚠️ ❌ 💾)

---

## ✅ Acceptance Criteria

### Functionality:
- [ ] ViewModel compiles without errors
- [ ] Cache checking works (returns nil if no cache)
- [ ] Cache saving works (stores in database)
- [ ] Mock insights generate successfully
- [ ] All published properties update correctly

### Error Handling:
- [ ] Missing Supabase client handled
- [ ] Empty entries list handled
- [ ] Network errors don't crash app
- [ ] Error messages are user-friendly

### Logging:
- [ ] Cache hits logged: "✅ Cache HIT"
- [ ] Cache misses logged: "⚠️ Cache MISS"
- [ ] Cache saves logged: "💾 Saved to cache"
- [ ] Errors logged: "❌ Error: ..."

---

## 🧪 Testing Checklist

### Unit Tests:
- [ ] Test cache hit scenario
- [ ] Test cache miss scenario
- [ ] Test cache saving
- [ ] Test staleness detection
- [ ] Test error cases

### Manual Tests:
1. **First Load**:
   - [ ] Console shows "⚠️ Cache MISS"
   - [ ] Loading state activates
   - [ ] Mock insights generate
   - [ ] Console shows "💾 Saved to cache"
   - [ ] insights property populated

2. **Second Load**:
   - [ ] Console shows "✅ Cache HIT"
   - [ ] No loading state
   - [ ] Insights populate instantly
   - [ ] Same data as first load

3. **Error Handling**:
   - [ ] Disconnect network → error message shows
   - [ ] Empty entries → handled gracefully
   - [ ] Invalid cache data → generates new

---

## 📦 Deliverables

### Files Created:
```
withMemento/
├── Models/
│   └── Insights.swift (NEW)
└── ViewModels/
    └── InsightsViewModel.swift (NEW)
```

### Code Complete:
- ✅ Data models defined
- ✅ ViewModel class created
- ✅ Cache checking implemented
- ✅ Cache saving implemented
- ✅ Mock generator implemented
- ✅ Error handling added
- ✅ Logging added

---

## 🔗 References

- **Full Code**: See `INSIGHTS_CACHING_INTEGRATION.md` (Step 1)
- **Database Functions**: See `DATABASE_OPTIMIZATION.md` (SQL Functions)
- **Next Sprint**: Sprint 2 - InsightsView Integration

---

## 📝 Notes

### Cache TTL Strategy:
- **7 days** for journal summaries (insights don't change quickly)
- Auto-invalidates when entries created/updated (via trigger)
- Manual refresh via pull-to-refresh

### Performance Target:
- Cache hit: < 100ms
- Cache miss: 2-5 seconds (first time)
- Cache save: < 200ms (background)

---

## 🚀 Getting Started

1. Open Xcode
2. Create `Models/Insights.swift`
3. Copy data model code from integration guide
4. Create `ViewModels/InsightsViewModel.swift`
5. Copy ViewModel code from integration guide
6. Build project (⌘B)
7. Fix any compilation errors
8. Add console logs
9. Test with sample data

---

**Ready to start?** Copy the full code from `INSIGHTS_CACHING_INTEGRATION.md` → Step 1
