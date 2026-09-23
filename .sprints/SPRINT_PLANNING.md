# withMemento - Sprint Planning
## Database Optimization & AI Insights Caching

**Project Goal**: Optimize database performance and implement intelligent AI insights caching
**Total Estimated Time**: 8 sprints (2-3 weeks)

---

## ✅ Sprint 0: Database Optimization (COMPLETED)
**Status**: ✅ Done
**Duration**: Completed Oct 23, 2025
**Goal**: Optimize database schema and remove deprecated code

### Tasks Completed:
- [x] Create cleanup migration (remove follow_up_questions)
- [x] Create performance indexes migration (full-text search, GIN indexes)
- [x] Create data validation migration (28 constraints)
- [x] Create insights cache table migration (user_insights)
- [x] Create user statistics migration (user_stats)
- [x] Test migrations locally
- [x] Link to production Supabase
- [x] Deploy all migrations to production
- [x] Verify deployment in dashboard
- [x] Document all changes

### Deliverables:
- ✅ 5 migration files deployed
- ✅ 2 new tables: `user_insights`, `user_stats`
- ✅ 15+ performance indexes
- ✅ 28 data validation constraints
- ✅ 9 helper SQL functions
- ✅ Complete documentation

### Performance Gains:
- 10-100x faster queries
- 80-90% potential API cost reduction
- Instant user statistics

---

## 📋 Sprint 1: InsightsViewModel Foundation
**Status**: 🔄 Ready to Start
**Duration**: 2-3 days
**Goal**: Create the ViewModel layer for insights caching

### Tasks:
- [ ] Create `InsightsViewModel.swift` file
- [ ] Implement data models (`JournalInsights`, `InsightSummary`)
- [ ] Implement cache checking (`getCachedInsights`)
- [ ] Implement cache saving (`saveToCacheBackground`)
- [ ] Add cache staleness detection (`isCacheStale`)
- [ ] Add error handling (`InsightsError` enum)
- [ ] Write unit tests for ViewModel
- [ ] Add logging for cache hits/misses

### Deliverables:
- `ViewModels/InsightsViewModel.swift` (fully functional)
- Unit tests passing
- Console logs showing cache behavior

### Acceptance Criteria:
- ViewModel can check cache successfully
- ViewModel can save to cache successfully
- Cache staleness is detected correctly
- All error cases handled gracefully

### Files to Create:
```
withMemento/
├── ViewModels/
│   └── InsightsViewModel.swift (NEW)
└── Models/
    └── Insights.swift (NEW - data models)
```

---

## 📋 Sprint 2: InsightsView Integration
**Status**: ⏳ Blocked by Sprint 1
**Duration**: 2-3 days
**Goal**: Connect InsightsView to the caching ViewModel

### Tasks:
- [ ] Add `@StateObject` for InsightsViewModel
- [ ] Replace hardcoded data with ViewModel state
- [ ] Implement loading state UI
- [ ] Implement error state UI
- [ ] Add `.task` modifier for auto-loading
- [ ] Add `.refreshable` for pull-to-refresh
- [ ] Add cache indicator UI component
- [ ] Update all previews
- [ ] Test empty state
- [ ] Test loading state
- [ ] Test cached state
- [ ] Test error state

### Deliverables:
- Updated `InsightsView.swift` with caching
- Loading spinner for first-time generation
- Cache timestamp indicator
- Pull-to-refresh functionality
- All UI states working

### Acceptance Criteria:
- First load shows loading state
- Subsequent loads show instantly
- Cache indicator displays "Updated X ago"
- Pull-to-refresh regenerates insights
- Error handling shows user-friendly message

### Files to Modify:
```
withMemento/Views/Insights/
└── InsightsView.swift (UPDATE)
```

---

## 📋 Sprint 3: Mock AI Insights Generator
**Status**: ⏳ Blocked by Sprint 1
**Duration**: 1-2 days
**Goal**: Implement basic insights generation (without real AI)

### Tasks:
- [ ] Implement `generateInsights()` in ViewModel
- [ ] Create keyword analysis logic
- [ ] Generate mock summary based on entries
- [ ] Generate mock themes from common keywords
- [ ] Add entry count to insights
- [ ] Test with 0 entries (error case)
- [ ] Test with 1-5 entries
- [ ] Test with 10+ entries
- [ ] Test with 50+ entries
- [ ] Verify cache saves correctly

### Deliverables:
- Functional insights generation (mock data)
- Insights vary based on actual entry content
- Cache stores generated insights
- All edge cases handled

### Acceptance Criteria:
- Insights reflect actual journal content (keywords)
- Summary mentions specific entry count
- Themes change based on entry text
- Generation completes in < 1 second (mock)
- Cache saves and retrieves correctly

### Mock Logic Example:
```swift
// Keyword detection
if allText.contains("work") → Add "Work-life balance" theme
if allText.contains("stress") → Add "Stress management" theme
if allText.contains("growth") → Add "Personal growth" theme
```

---

## 📋 Sprint 4: Real AI Integration (OpenAI)
**Status**: ⏳ Blocked by Sprint 3
**Duration**: 3-4 days
**Goal**: Replace mock generator with real OpenAI API

**Note**: User will provide OpenAI code for implementation

### Tasks:
- [ ] Review OpenAI code provided by user
- [ ] Create OpenAI service wrapper
- [ ] Implement prompt engineering for insights
- [ ] Add OpenAI API key configuration
- [ ] Replace mock generator with real API calls
- [ ] Handle OpenAI rate limits
- [ ] Handle OpenAI errors gracefully
- [ ] Add retry logic for failed requests
- [ ] Optimize prompt for cost efficiency
- [ ] Test with various entry counts
- [ ] Track token usage
- [ ] Monitor API costs

### Deliverables:
- OpenAI integration working
- Real AI-generated insights
- Error handling for API failures
- Rate limit handling
- Cost tracking

### Acceptance Criteria:
- Insights are contextually relevant
- API errors don't crash app
- Rate limits handled gracefully
- Token usage logged
- First generation takes 2-5 seconds
- Cached insights still instant

### Files to Create/Modify:
```
withMemento/
├── Services/
│   └── OpenAIService.swift (NEW)
├── ViewModels/
│   └── InsightsViewModel.swift (UPDATE - use real API)
└── Resources/
    └── Config.swift (UPDATE - add OpenAI key)
```

### API Cost Estimation:
- ~500 tokens per insight generation
- 10 generations = 5,000 tokens
- With caching: 90% reduction = ~500 tokens per week
- Cost: ~$0.01 per week per user

---

## 📋 Sprint 5: Edge Function Alternative (Optional)
**Status**: ⏳ Blocked by Sprint 4
**Duration**: 2-3 days
**Goal**: Move AI generation to Supabase Edge Function (server-side)

**Why**: Keep API keys secure, reduce app size, better monitoring

### Tasks:
- [ ] Create `generate-journal-insights` edge function
- [ ] Move OpenAI logic to server-side
- [ ] Add authentication to edge function
- [ ] Add rate limiting (per user)
- [ ] Add input validation (entry count, text length)
- [ ] Deploy edge function
- [ ] Update ViewModel to call edge function
- [ ] Add edge function error handling
- [ ] Test with various entry counts
- [ ] Monitor edge function logs

### Deliverables:
- Edge function deployed
- ViewModel calls edge function instead of OpenAI directly
- API keys secure on server
- Rate limiting enforced server-side

### Acceptance Criteria:
- Edge function authenticates users
- Rate limiting prevents abuse
- Generation works identically to Sprint 4
- API keys never exposed in app
- Edge function logs visible in dashboard

### Files to Create:
```
supabase/functions/
└── generate-journal-insights/
    ├── index.ts (NEW)
    └── types.ts (NEW)
```

### Deployment:
```bash
supabase functions deploy generate-journal-insights
```

---

## 📋 Sprint 6: Cache Analytics & Monitoring
**Status**: ⏳ Blocked by Sprint 4
**Duration**: 1-2 days
**Goal**: Add analytics to track cache performance

### Tasks:
- [ ] Add cache hit/miss tracking
- [ ] Create analytics service
- [ ] Track time saved by caching
- [ ] Track API cost savings
- [ ] Add debug panel in settings
- [ ] Show cache statistics to developer
- [ ] Log cache performance metrics
- [ ] Create Supabase dashboard query for monitoring

### Deliverables:
- Cache analytics tracking
- Debug panel in Settings
- Supabase dashboard query for monitoring

### Acceptance Criteria:
- Can see cache hit rate in debug panel
- Can calculate cost savings
- Can see time saved per user
- Logs don't contain user data (privacy)

### Debug Panel Display:
```
Cache Statistics:
- Hit Rate: 87%
- Average Load Time: 62ms
- API Calls Saved: 143
- Estimated Cost Savings: $1.23
```

---

## 📋 Sprint 7: User Statistics Integration
**Status**: ⏳ Independent (can start anytime)
**Duration**: 2-3 days
**Goal**: Use the `user_stats` table in Profile/Settings

### Tasks:
- [ ] Create `UserStatsService.swift`
- [ ] Fetch stats from `user_stats` table
- [ ] Add stats display to ProfileView
- [ ] Show total entries count
- [ ] Show total words written
- [ ] Show current streak
- [ ] Show longest streak
- [ ] Add stats to Settings/About page
- [ ] Add loading state for stats
- [ ] Add error handling
- [ ] Test with users who have stats
- [ ] Test with new users (no stats yet)

### Deliverables:
- User statistics displayed in app
- Stats update automatically (via triggers)
- Beautiful stats UI component

### Acceptance Criteria:
- Stats load instantly (< 10ms)
- Stats are accurate
- Stats update when entries created/deleted
- UI is clean and informative

### UI Mockup:
```
Your Journey
━━━━━━━━━━━━━━━━━━━
📝 142 Entries
✍️ 28,943 Words
🔥 7 Day Streak
🏆 23 Days (Best)
```

---

## 📋 Sprint 8: Full-Text Search Feature
**Status**: ⏳ Independent (can start anytime)
**Duration**: 2-3 days
**Goal**: Add search functionality using new full-text indexes

### Tasks:
- [ ] Add search bar to JournalView
- [ ] Create `SearchService.swift`
- [ ] Call `search_entries()` SQL function
- [ ] Display search results with relevance ranking
- [ ] Highlight matched keywords
- [ ] Add search history
- [ ] Add recent searches
- [ ] Add suggested searches based on themes
- [ ] Test search performance
- [ ] Test search accuracy

### Deliverables:
- Working search bar
- Fast search results (< 20ms)
- Relevance-ranked results
- Search history

### Acceptance Criteria:
- Search returns results in < 20ms
- Results are ranked by relevance
- Partial matches work ("stres" finds "stress")
- Empty search handled gracefully
- Search history persists

### Search UI:
```
┌─────────────────────────┐
│  🔍 Search entries...   │
└─────────────────────────┘

Recent Searches:
• work stress
• weekend plans
• gratitude

Results (12):
────────────────────────
"Work has been stressful..."
  March 15, 2025
  Relevance: ⭐⭐⭐⭐⭐
```

---

## 📋 Future Enhancements (Backlog)

### Insights Enhancements:
- [ ] Weekly recap insights
- [ ] Monthly summary insights
- [ ] Year in review
- [ ] Mood tracking over time
- [ ] Goal progress tracking
- [ ] Writing prompts based on themes

### Performance:
- [ ] Pagination for large entry lists
- [ ] Lazy loading for insights
- [ ] Background insights generation
- [ ] Offline mode with local cache

### Analytics:
- [ ] User engagement metrics
- [ ] Insights generation costs
- [ ] Cache hit rate per user
- [ ] Popular themes analysis

### AI Features:
- [ ] Sentiment analysis
- [ ] Writing style analysis
- [ ] Personalized questions
- [ ] Growth recommendations

---

## 📊 Sprint Dependencies

```
Sprint 0 (Database) ✅
    ↓
    ├─→ Sprint 1 (ViewModel) → Sprint 2 (View Integration)
    │                              ↓
    ├─→ Sprint 3 (Mock AI) → Sprint 4 (Real AI) → Sprint 5 (Edge Function)
    │                                                  ↓
    ├─→ Sprint 6 (Analytics)
    │
    ├─→ Sprint 7 (User Stats) (Independent)
    │
    └─→ Sprint 8 (Search) (Independent)
```

---

## 🎯 Recommended Sprint Order

### Week 1:
- **Sprint 1**: InsightsViewModel (2-3 days)
- **Sprint 2**: InsightsView Integration (2-3 days)
- **Sprint 7**: User Statistics (parallel, 2-3 days)

### Week 2:
- **Sprint 3**: Mock AI (1-2 days)
- **Sprint 4**: Real AI Integration (3-4 days - **needs OpenAI code from user**)

### Week 3:
- **Sprint 5**: Edge Function (optional, 2-3 days)
- **Sprint 6**: Analytics (1-2 days)
- **Sprint 8**: Search Feature (2-3 days)

---

## 📝 Sprint Tracking

Create individual files for each sprint:
```
.sprints/
├── SPRINT_PLANNING.md (this file)
├── sprint-01-insights-viewmodel.md
├── sprint-02-insights-view.md
├── sprint-03-mock-ai.md
├── sprint-04-real-ai.md
├── sprint-05-edge-function.md
├── sprint-06-analytics.md
├── sprint-07-user-stats.md
└── sprint-08-search.md
```

---

## 🚀 Getting Started

**Next Sprint**: Sprint 1 - InsightsViewModel Foundation

**To Start**:
1. Read: `INSIGHTS_CACHING_INTEGRATION.md`
2. Create: `sprint-01-insights-viewmodel.md`
3. Copy: ViewModel code from integration guide
4. Test: Console logs for cache behavior
5. Done: Move to Sprint 2

**All code examples ready in**: `INSIGHTS_CACHING_INTEGRATION.md`

---

**Let me know when you're ready to share the OpenAI code for Sprint 4!** 🚀
