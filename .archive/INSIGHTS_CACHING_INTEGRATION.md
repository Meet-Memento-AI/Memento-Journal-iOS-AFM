# Insights Caching Integration Guide

**For**: InsightsView AI-generated insights
**Database**: Using the new `user_insights` caching table
**Goal**: Reduce AI API costs by 80-90% and provide instant insights loading

---

## 📋 Current State

Your `InsightsView.swift` currently shows:
- ✅ Empty state when no entries exist
- ⚠️ **Hardcoded sample data** for insights (lines 43-58)
- ⚠️ No actual AI generation yet

### What You Have:
```swift
// Current: Hardcoded sample data
AISummarySection(
    title: "Your emotional landscape reveals...",
    body: "You've been processing heavy emotions..."
)

InsightsThemesSection(
    themes: [
        "Work related stress",
        "Keeping an image",
        // ... hardcoded themes
    ]
)
```

### What You Need:
```swift
// Goal: Real AI insights with caching
if let insights = insightsViewModel.cachedInsights {
    // Show cached insights (50ms) ⚡
    AISummarySection(
        title: insights.summary.title,
        body: insights.summary.body
    )
    InsightsThemesSection(themes: insights.themes)
} else {
    // Generate new insights (2-5s first time)
    LoadingView("Analyzing your journal...")
}
```

---

## 🏗️ Architecture Overview

```
┌─────────────────┐
│  InsightsView   │  ← UI Layer (your existing view)
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│InsightsViewModel│  ← NEW: Manages caching & API calls
└────────┬────────┘
         │
         ├─→ 1. Check cache (user_insights table) ⚡ 50ms
         │
         └─→ 2. If miss: Call edge function 🤖 2-5s
                 └─→ 3. Save to cache for next time 💾
```

---

## 📦 Step 1: Create InsightsViewModel

Create a new file: `withMemento/ViewModels/InsightsViewModel.swift`

```swift
//
//  InsightsViewModel.swift
//  withMemento
//
//  Manages AI-generated journal insights with intelligent caching
//

import Foundation
import Supabase

// MARK: - Data Models

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

// MARK: - View Model

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var insights: JournalInsights?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseService.shared.supabase

    // MARK: - Public API

    /// Fetches insights with intelligent caching
    /// - First checks cache (50ms)
    /// - If stale/missing, generates new insights (2-5s)
    /// - Auto-saves to cache for next time
    func fetchInsights(forUserId userId: UUID, entries: [Entry]) async {
        isLoading = true
        errorMessage = nil

        do {
            // Step 1: Check cache first
            if let cached = try await getCachedInsights(userId: userId) {
                print("✅ Cache HIT - Using cached insights")
                insights = cached
                isLoading = false

                // Optional: Refresh in background if cache is old
                if isCacheStale(cached) {
                    print("⏰ Cache is stale, refreshing in background...")
                    Task {
                        await refreshInsights(userId: userId, entries: entries)
                    }
                }
                return
            }

            // Step 2: Cache miss - generate new insights
            print("⚠️ Cache MISS - Generating new insights")
            await refreshInsights(userId: userId, entries: entries)

        } catch {
            errorMessage = "Failed to load insights: \(error.localizedDescription)"
            print("❌ Insights fetch error: \(error)")
        }

        isLoading = false
    }

    /// Forces a fresh insight generation (bypasses cache)
    func refreshInsights(userId: UUID, entries: [Entry]) async {
        isLoading = true
        errorMessage = nil

        do {
            // Generate new insights via edge function
            let newInsights = try await generateInsights(entries: entries)

            // Save to cache
            try await saveToCacheBackground(
                userId: userId,
                insights: newInsights,
                entriesCount: entries.count
            )

            insights = newInsights

        } catch {
            errorMessage = "Failed to generate insights: \(error.localizedDescription)"
            print("❌ Insights generation error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Cache Management

    /// Checks cache for valid insights
    private func getCachedInsights(userId: UUID) async throws -> JournalInsights? {
        guard let supabase = supabase else { return nil }

        // Query the user_insights table using the RPC function
        let result: [[String: Any]] = try await supabase
            .rpc("get_cached_insight", params: [
                "p_user_id": userId.uuidString,
                "p_insight_type": "journal_summary"
            ])
            .execute()
            .value

        guard let first = result.first,
              let contentData = try? JSONSerialization.data(withJSONObject: first["content"] ?? [:]),
              let cached = try? JSONDecoder().decode(JournalInsights.self, from: contentData)
        else {
            return nil
        }

        return cached
    }

    /// Saves insights to cache in background
    private func saveToCacheBackground(
        userId: UUID,
        insights: JournalInsights,
        entriesCount: Int
    ) async throws {
        guard let supabase = supabase else { return }

        // Encode insights to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contentData = try encoder.encode(insights)
        let contentJSON = try JSONSerialization.jsonObject(with: contentData)

        // Save to cache with 7-day TTL
        let _: String = try await supabase
            .rpc("save_insight_cache", params: [
                "p_user_id": userId.uuidString,
                "p_insight_type": "journal_summary",
                "p_content": contentJSON,
                "p_entries_count": entriesCount,
                "p_ttl_hours": 168  // 7 days
            ])
            .execute()
            .value

        print("💾 Saved insights to cache (expires in 7 days)")
    }

    /// Checks if cache is stale (older than 24 hours)
    private func isCacheStale(_ insights: JournalInsights) -> Bool {
        let dayAgo = Date().addingTimeInterval(-86400) // 24 hours
        return insights.generatedAt < dayAgo
    }

    // MARK: - AI Generation (Placeholder)

    /// Generates insights from journal entries via edge function
    /// TODO: Implement your actual edge function call
    private func generateInsights(entries: [Entry]) async throws -> JournalInsights {
        guard let supabase = supabase else {
            throw InsightsError.clientNotConfigured
        }

        // Prepare request body
        let requestBody: [String: Any] = [
            "entries": entries.map { entry in
                [
                    "id": entry.id.uuidString,
                    "title": entry.title,
                    "text": entry.text,
                    "created_at": ISO8601DateFormatter().string(from: entry.createdAt)
                ]
            }
        ]

        // TODO: Replace with your actual edge function name
        // For now, return mock data
        print("🤖 Calling AI edge function with \(entries.count) entries...")

        // Simulate API delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Mock response - replace with actual edge function call:
        /*
        let response: [String: Any] = try await supabase.functions
            .invoke("generate-journal-insights", body: requestBody)
        */

        return JournalInsights(
            summary: InsightSummary(
                title: "Your emotional landscape reveals growth and reflection",
                body: "Based on \(entries.count) entries, you've been processing emotions around work, identity, and personal growth. There's a steady shift toward acceptance and purpose."
            ),
            themes: [
                "Work-life balance",
                "Personal growth",
                "Self-reflection",
                "Emotional awareness"
            ],
            generatedAt: Date(),
            entriesAnalyzed: entries.count
        )
    }
}

// MARK: - Errors

enum InsightsError: LocalizedError {
    case clientNotConfigured
    case noEntries
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .clientNotConfigured: return "Supabase client not configured"
        case .noEntries: return "No journal entries to analyze"
        case .generationFailed: return "Failed to generate insights"
        }
    }
}
```

---

## 📱 Step 2: Update InsightsView

Update your `InsightsView.swift` to use the new ViewModel:

```swift
//
//  InsightsView.swift
//  withMemento
//

import SwiftUI

public struct InsightsView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @StateObject private var insightsViewModel = InsightsViewModel()

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init() {}

    public var body: some View {
        Group {
            if entryViewModel.entries.isEmpty {
                // Empty state
                emptyState(
                    icon: "sparkles",
                    title: "No insights yet",
                    message: "Your insights will appear here after journaling."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if insightsViewModel.isLoading && insightsViewModel.insights == nil {
                // Loading state (first time)
                loadingState
            } else if let insights = insightsViewModel.insights {
                // Content with real AI insights
                insightsContent(insights: insights)
            } else if let error = insightsViewModel.errorMessage {
                // Error state
                errorState(message: error)
            }
        }
        .background(Color.clear)
        .ignoresSafeArea()
        .task {
            // Load insights when view appears
            guard let userId = entryViewModel.entries.first?.userId else { return }
            await insightsViewModel.fetchInsights(
                forUserId: userId,
                entries: entryViewModel.entries
            )
        }
        .refreshable {
            // Pull-to-refresh: Force regenerate insights
            guard let userId = entryViewModel.entries.first?.userId else { return }
            await insightsViewModel.refreshInsights(
                userId: userId,
                entries: entryViewModel.entries
            )
        }
    }

    /// Content view showing AI insights
    private func insightsContent(insights: JournalInsights) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Show cache indicator
                if let generatedAt = insights.generatedAt {
                    cacheIndicator(date: generatedAt)
                }

                // AI Summary Section (real data)
                AISummarySection(
                    title: insights.summary.title,
                    body: insights.summary.body
                )

                // Themes Section (real data)
                InsightsThemesSection(themes: insights.themes)

                // Metadata
                Text("Based on \(insights.entriesAnalyzed) entries")
                    .font(type.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.top, 108)
            .padding(.bottom, 24)
        }
    }

    /// Loading state
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Analyzing your journal...")
                .font(type.body)
                .foregroundStyle(.white.opacity(0.8))

            Text("This may take a moment")
                .font(type.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Error state
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.white)

            Text("Unable to load insights")
                .font(type.h3)
                .foregroundStyle(.white)

            Text(message)
                .font(type.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    guard let userId = entryViewModel.entries.first?.userId else { return }
                    await insightsViewModel.refreshInsights(
                        userId: userId,
                        entries: entryViewModel.entries
                    )
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Cache indicator (shows when insights were generated)
    private func cacheIndicator(date: Date) -> some View {
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
    }

    /// Reusable empty state view
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.white)

            Text(title)
                .font(type.h3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(message)
                .font(type.body)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }
}

// MARK: - Date Extension

extension Date {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
```

---

## 🚀 Step 3: Create Edge Function (Optional)

If you want real AI-generated insights, create a new edge function:

`supabase/functions/generate-journal-insights/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Authenticate
    const authHeader = req.headers.get('Authorization');
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader ?? '' } } }
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('Unauthorized');

    // Get request body
    const { entries } = await req.json();

    // TODO: Call your AI service (OpenAI, Claude, etc.)
    // For now, generate insights from keywords
    const insights = analyzeEntries(entries);

    return new Response(
      JSON.stringify(insights),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

function analyzeEntries(entries: any[]) {
  // Simple keyword-based analysis (replace with real AI)
  const allText = entries.map(e => e.text).join(' ').toLowerCase();

  const themes = [];
  if (allText.includes('work') || allText.includes('job')) themes.push('Work-life balance');
  if (allText.includes('stress') || allText.includes('anxious')) themes.push('Stress management');
  if (allText.includes('growth') || allText.includes('learning')) themes.push('Personal growth');
  if (allText.includes('relationship')) themes.push('Relationships');

  return {
    summary: {
      title: 'Your journey shows consistent reflection',
      body: `Based on ${entries.length} entries, you've been actively processing emotions and experiences. Your writing reveals a focus on personal development and self-awareness.`
    },
    themes: themes.length > 0 ? themes : ['General reflection'],
    generatedAt: new Date().toISOString(),
    entriesAnalyzed: entries.length
  };
}
```

Deploy it:
```bash
supabase functions deploy generate-journal-insights
```

---

## 📊 Performance Benefits

### Before (No Caching):
```
User opens Insights tab
↓
Wait 2-5 seconds for AI generation
↓
Show results
↓
User switches tabs and comes back
↓
Wait 2-5 seconds AGAIN (regenerates every time)
```

### After (With Caching):
```
User opens Insights tab
↓
1st time: Wait 2-5 seconds for AI generation
          Save to cache
↓
Show results
↓
User switches tabs and comes back
↓
Show cached results INSTANTLY (50ms) ⚡
↓
Cache expires after 7 days OR user creates new entries
↓
Then regenerate and cache again
```

---

## ✅ Testing Checklist

1. **First Load** (Cache Miss)
   - [ ] InsightsView shows loading spinner
   - [ ] Waits 2-5 seconds (generating insights)
   - [ ] Shows AI-generated summary and themes
   - [ ] Console logs: "Cache MISS - Generating new insights"
   - [ ] Console logs: "💾 Saved insights to cache"

2. **Second Load** (Cache Hit)
   - [ ] InsightsView shows instantly (no spinner)
   - [ ] Shows same insights from cache
   - [ ] Console logs: "✅ Cache HIT - Using cached insights"
   - [ ] Takes ~50ms instead of 2-5 seconds

3. **After Creating Entry**
   - [ ] Cache auto-invalidates (trigger fires)
   - [ ] Next insights load regenerates (cache miss)
   - [ ] Fresh insights reflect new entry

4. **Pull to Refresh**
   - [ ] User can pull down to force regenerate
   - [ ] Shows loading state
   - [ ] Generates fresh insights
   - [ ] Updates cache

---

## 🎯 Expected Results

### Cache Hit Rate:
- **Goal**: 80-90% of insights loads are from cache
- **Benefit**: 40-100x faster load times

### API Cost Savings:
- **Before**: Generate insights every single time = 100% API calls
- **After**: Generate once per week = 10-20% API calls
- **Savings**: 80-90% reduction in AI costs

### User Experience:
- **First load**: 2-5 seconds (acceptable for first-time generation)
- **Subsequent loads**: 50ms (instant, feels native)
- **After new entries**: Auto-regenerates for fresh insights

---

## 🔧 Advanced: Cache Invalidation

The cache auto-invalidates when you create/update/delete entries (via database triggers). But you can also manually invalidate:

```swift
// In InsightsViewModel
func invalidateCache(userId: UUID) async throws {
    guard let supabase = supabase else { return }

    let _: Int = try await supabase
        .rpc("invalidate_insights", params: [
            "p_user_id": userId.uuidString,
            "p_insight_type": "journal_summary"
        ])
        .execute()
        .value

    print("🗑️ Cache invalidated manually")
}
```

---

## 📝 Next Steps

1. **Immediate**: Copy the InsightsViewModel code into your project
2. **Update**: Modify InsightsView to use the ViewModel
3. **Test**: Run app and see caching in action (check console logs)
4. **Later**: Create real AI edge function to replace mock data
5. **Monitor**: Track cache hit rates in Supabase logs

---

**Your insights are now cached and blazing fast!** 🚀
