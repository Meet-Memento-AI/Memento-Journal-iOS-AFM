# Sprint 2: InsightsView Integration

**Status**: ⏳ Blocked by Sprint 1
**Duration**: 2-3 days
**Sprint Goal**: Connect InsightsView to the caching ViewModel

---

## 🎯 Objectives

1. Integrate InsightsViewModel into InsightsView
2. Replace hardcoded data with real cached data
3. Add loading, error, and cached states
4. Implement pull-to-refresh
5. Add cache indicator UI

---

## 📋 Tasks Breakdown

### Task 2.1: Add ViewModel to View (30 mins)
**File**: `withMemento/Views/Insights/InsightsView.swift`

- [ ] Add `@StateObject` for InsightsViewModel
- [ ] Keep existing `@EnvironmentObject` for EntryViewModel
- [ ] Update init if needed

**Code**:
```swift
@StateObject private var insightsViewModel = InsightsViewModel()
@EnvironmentObject var entryViewModel: EntryViewModel
```

### Task 2.2: Replace Hardcoded Data (1 hour)
**Current Lines**: 43-58

- [ ] Remove hardcoded `AISummarySection` data
- [ ] Remove hardcoded `InsightsThemesSection` themes
- [ ] Use `insightsViewModel.insights` instead
- [ ] Add nil check for insights

**Before**:
```swift
AISummarySection(
    title: "Your emotional landscape reveals...",
    body: "You've been processing heavy emotions..."
)
```

**After**:
```swift
if let insights = insightsViewModel.insights {
    AISummarySection(
        title: insights.summary.title,
        body: insights.summary.body
    )
}
```

### Task 2.3: Add Loading State UI (1 hour)

- [ ] Create `loadingState` computed property
- [ ] Show when `isLoading && insights == nil`
- [ ] Add spinner
- [ ] Add "Analyzing your journal..." text
- [ ] Add subtitle hint

**UI Components**:
```swift
VStack(spacing: 16) {
    ProgressView()
        .scaleEffect(1.5)
        .tint(.white)

    Text("Analyzing your journal...")
        .font(type.body)

    Text("This may take a moment")
        .font(type.caption)
        .foregroundStyle(.white.opacity(0.6))
}
```

### Task 2.4: Add Error State UI (1 hour)

- [ ] Create `errorState(message:)` function
- [ ] Show when `errorMessage != nil`
- [ ] Add error icon
- [ ] Show error message
- [ ] Add "Try Again" button

**UI Components**:
```swift
VStack(spacing: 12) {
    Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 36))

    Text("Unable to load insights")
        .font(type.h3)

    Text(errorMessage)
        .font(type.caption)

    Button("Try Again") {
        // Retry logic
    }
}
```

### Task 2.5: Add Cache Indicator (1 hour)

- [ ] Create `cacheIndicator(date:)` function
- [ ] Show when insights exist
- [ ] Display "Updated X ago"
- [ ] Use relative time formatting
- [ ] Style with semi-transparent background

**UI**:
```swift
HStack(spacing: 6) {
    Image(systemName: "clock")
        .font(.system(size: 12))
    Text("Updated \(date.timeAgoDisplay)")
        .font(type.caption)
}
.foregroundStyle(.white.opacity(0.5))
.padding(.horizontal, 12)
.padding(.vertical, 6)
.background(.white.opacity(0.1))
.cornerRadius(12)
```

### Task 2.6: Implement Auto-Loading (30 mins)

- [ ] Add `.task` modifier to view
- [ ] Call `fetchInsights()` when view appears
- [ ] Get userId from entries
- [ ] Pass all entries
- [ ] Handle case when no entries exist

**Code**:
```swift
.task {
    guard let userId = entryViewModel.entries.first?.userId else { return }
    await insightsViewModel.fetchInsights(
        forUserId: userId,
        entries: entryViewModel.entries
    )
}
```

### Task 2.7: Implement Pull-to-Refresh (30 mins)

- [ ] Add `.refreshable` modifier
- [ ] Call `refreshInsights()` (force regenerate)
- [ ] Show standard iOS refresh control
- [ ] Ensure it works with ScrollView

**Code**:
```swift
.refreshable {
    guard let userId = entryViewModel.entries.first?.userId else { return }
    await insightsViewModel.refreshInsights(
        userId: userId,
        entries: entryViewModel.entries
    )
}
```

### Task 2.8: Add Metadata Display (30 mins)

- [ ] Show "Based on X entries" text
- [ ] Style with caption font
- [ ] Place at bottom of insights
- [ ] Use semi-transparent color

### Task 2.9: Update Main Body Logic (1 hour)

- [ ] Update `body` computed property
- [ ] Handle all states: empty, loading, cached, error
- [ ] Ensure smooth transitions
- [ ] Test state changes

**State Priority**:
```
1. Empty entries → Empty state
2. Loading + no insights → Loading state
3. Has insights → Content state
4. Has error → Error state
```

### Task 2.10: Update Previews (30 mins)

- [ ] Update "Empty State" preview
- [ ] Update "With Insights" preview
- [ ] Update "Dark Mode" preview
- [ ] Add "Loading State" preview
- [ ] Add "Error State" preview
- [ ] Add "Cached State" preview

---

## ✅ Acceptance Criteria

### Functionality:
- [ ] View compiles without errors
- [ ] Empty state shows when no entries
- [ ] Loading state shows on first load
- [ ] Insights display after loading completes
- [ ] Cache indicator shows relative time
- [ ] Pull-to-refresh regenerates insights
- [ ] Error state shows on failure
- [ ] Retry button works in error state

### UI/UX:
- [ ] Loading spinner is centered
- [ ] All text is readable
- [ ] Cache indicator is subtle
- [ ] Transitions are smooth
- [ ] Pull-to-refresh feels native
- [ ] Error messages are user-friendly

### Performance:
- [ ] First load: Shows loading state
- [ ] Second load: Shows instantly (cached)
- [ ] No janky animations
- [ ] Scroll performance is smooth

---

## 🧪 Testing Checklist

### Manual Testing:

1. **Empty State Test**:
   - [ ] Delete all entries
   - [ ] Open Insights tab
   - [ ] See empty state message
   - [ ] Icon and text display correctly

2. **First Load Test (Cache Miss)**:
   - [ ] Fresh install or clear cache
   - [ ] Create 3-5 entries
   - [ ] Open Insights tab
   - [ ] See loading spinner
   - [ ] Wait 2-5 seconds
   - [ ] See insights appear
   - [ ] Cache indicator shows "Updated just now"

3. **Second Load Test (Cache Hit)**:
   - [ ] Close and reopen Insights tab
   - [ ] Insights appear instantly (no spinner)
   - [ ] Cache indicator shows "Updated X ago"
   - [ ] Same insights as before

4. **Pull-to-Refresh Test**:
   - [ ] Pull down on Insights view
   - [ ] See refresh indicator
   - [ ] Wait for regeneration
   - [ ] New insights appear
   - [ ] Cache indicator updates to "just now"

5. **Error State Test**:
   - [ ] Turn off WiFi
   - [ ] Clear app cache
   - [ ] Open Insights tab
   - [ ] See error state
   - [ ] Error message is clear
   - [ ] Tap "Try Again"
   - [ ] Turn on WiFi
   - [ ] Loading works now

6. **State Transitions**:
   - [ ] Empty → Has entries → Insights
   - [ ] Loading → Insights → Pull refresh → Insights
   - [ ] Insights → Error → Retry → Insights

---

## 📦 Deliverables

### Files Modified:
```
withMemento/Views/Insights/
└── InsightsView.swift (MAJOR UPDATE)
```

### Components Added:
- ✅ Loading state view
- ✅ Error state view
- ✅ Cache indicator component
- ✅ Pull-to-refresh functionality
- ✅ Metadata display

### States Implemented:
- ✅ Empty state (no entries)
- ✅ Loading state (first time)
- ✅ Content state (cached insights)
- ✅ Error state (with retry)

---

## 🎨 UI Mockup

### Loading State:
```
┌─────────────────────────┐
│                         │
│         [Spinner]       │
│                         │
│  Analyzing your journal...│
│                         │
│  This may take a moment │
│                         │
└─────────────────────────┘
```

### Content State:
```
┌─────────────────────────┐
│ [Clock] Updated 2h ago  │ ← Cache indicator
│                         │
│ Your Journey Summary    │
│ ──────────────────────  │
│ Based on 15 entries...  │
│                         │
│ Themes:                 │
│ • Work-life balance     │
│ • Personal growth       │
│ • Self-reflection       │
│                         │
│ Based on 15 entries     │ ← Metadata
└─────────────────────────┘
```

### Error State:
```
┌─────────────────────────┐
│          ⚠️             │
│                         │
│ Unable to load insights │
│                         │
│ Failed to connect...    │
│                         │
│   [ Try Again ]         │
│                         │
└─────────────────────────┘
```

---

## 🔗 References

- **Full Code**: See `INSIGHTS_CACHING_INTEGRATION.md` (Step 2)
- **Previous Sprint**: Sprint 1 - InsightsViewModel
- **Next Sprint**: Sprint 3 - Mock AI Generator

---

## 📝 Notes

### State Management:
- Use `@StateObject` for ViewModel (owned by view)
- Use `@EnvironmentObject` for shared data (EntryViewModel)
- Published properties auto-update UI

### Performance Tips:
- Use `.task` for async loading (cancels on view disappear)
- Use `.refreshable` for pull-to-refresh (native iOS feel)
- Cache indicator prevents confusion about stale data

### Accessibility:
- Ensure loading spinner is accessible
- Error messages are clear
- Retry button is tappable

---

## 🚀 Getting Started

1. Complete Sprint 1 first (InsightsViewModel)
2. Open `InsightsView.swift`
3. Add `@StateObject` for InsightsViewModel
4. Replace hardcoded data section
5. Add state views (loading, error)
6. Add `.task` and `.refreshable` modifiers
7. Test all states manually
8. Update previews

---

**Prerequisites**: Sprint 1 complete ✅
**Estimated Time**: 2-3 days
**Complexity**: Medium

---

**Ready to start?** Full code in `INSIGHTS_CACHING_INTEGRATION.md` → Step 2
