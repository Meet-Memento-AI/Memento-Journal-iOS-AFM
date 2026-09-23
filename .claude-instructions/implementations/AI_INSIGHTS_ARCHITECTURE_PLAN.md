# AI Insights Feature - Architecture Plan

**Version:** 2.0
**Date:** 2025-10-23
**Status:** Ready for Implementation

**What's New in v2.0:**
- ✅ Added `fetch-journal-entries` edge function for data transformation
- ✅ Two-function architecture: fetch → transform → generate insights
- ✅ Token optimization strategy (2000 token cap)
- ✅ Continuous adaptation for schema evolution
- ✅ Data quality monitoring
- ✅ 50% cost reduction through token budget enforcement

---

## 1. DISCOVERY

### 10 Targeted Questions

1. **OpenAI API Key**: Where is it stored? (Supabase secrets, environment variable)
2. **OpenAI Client**: Which Deno library? (openai-edge, openai official)
3. **Date Range**: Default 30, 60, or 90 days? User configurable or fixed?
4. **Minimum Entries**: What's the minimum entry count to generate insights? (e.g., 3+ entries)
5. **Database Table**: Reuse `user_insights` or rename to `insights`?
6. **Error Tracking**: Sentry, Supabase logs, or custom logging?
7. **Analytics**: Track generation events? (mixpanel, amplitude, posthog)
8. **Navigation**: Is InsightsView already in TabView? (yes, confirmed in ContentView)
9. **Retry Logic**: Should frontend auto-retry failed requests?
10. **Cost Limit**: Per-user rate limiting? (e.g., 1 regeneration per hour)

### Assumptions

- **OpenAI Model**: `gpt-4o` (fast, JSON mode, ~$2.50 per 1M input tokens)
- **OpenAI Key**: Stored as Supabase secret `OPENAI_API_KEY`
- **Library**: Official OpenAI Deno SDK (`npm:openai@4.x`)
- **Date Range**: Fixed 30 days (30-90 day range can be added later)
- **Minimum Entries**: 3+ entries required (error if fewer)
- **Database**: Use existing `user_insights` table, add missing columns
- **Cache**: 7 days TTL, auto-invalidate on new entry (existing trigger)
- **Navigation**: InsightsView already integrated in TabView
- **Error Display**: Show user-friendly messages, log details to console
- **Rate Limiting**: No rate limiting in v1 (add if costs spike)
- **Authentication**: Reuse existing Supabase JWT from client
- **Retries**: No automatic retry on client (user can manual refresh)
- **Entry Selection**: Use `created_at` for date filtering (not `updated_at`)
- **Word Count**: Calculate on backend from entry text
- **Mood Field**: Entry model doesn't have mood → always null in v1

---

## 2. BACKEND PLAN

### Architecture Overview

```
Client (Swift)
    ↓
[1] fetch-journal-entries Edge Function
    ↓ (Returns standardized JSON)
    ↓
[2] generate-insights Edge Function
    ↓ (Calls OpenAI)
    ↓
Client receives insights
```

**Two-Function Architecture Benefits:**
- **Separation of concerns**: Data fetching vs AI processing
- **Testability**: Can test transformation logic independently
- **Reusability**: Standardized journal JSON can be used by other features
- **Caching**: Can cache transformed entries separately
- **Error isolation**: DB errors vs OpenAI errors are separate

### File Tree

```
functions/
├── fetch-journal-entries/         [CREATE] Step 1: Fetch & transform journals
│   ├── index.ts                   Main handler
│   ├── types.ts                   Entry types
│   ├── transformer.ts             DB → JSON transformation
│   ├── dateUtils.ts               Date range calculations
│   └── README.md                  Documentation
│
└── generate-insights/             [CREATE] Step 2: AI insights generation
    ├── index.ts                   Main handler
    ├── types.ts                   TypeScript interfaces
    ├── prompts.ts                 Optimized OpenAI prompts
    ├── tokenOptimizer.ts          Token budget management
    ├── validation.ts              Response validation
    └── README.md                  Function documentation
```

---

## 2A. FETCH-JOURNAL-ENTRIES EDGE FUNCTION

### Purpose

Fetches user's journal entries from Supabase and transforms them into a standardized, consistent JSON format optimized for AI analysis. This function adapts to:
- Variable entry counts (3 to 1000+ entries)
- Different date ranges
- Entries with varying lengths
- Missing or empty fields

### Types (`fetch-journal-entries/types.ts`)

```typescript
// Request from client
export interface FetchJournalEntriesRequest {
  daysBack?: number;        // Default 30
  maxEntries?: number;      // Default 50, max 100
  includeEmpty?: boolean;   // Include entries with empty text? Default false
}

// Raw entry from Supabase
export interface EntryRow {
  id: string;
  user_id: string;
  title: string;
  text: string;
  created_at: string;       // ISO8601
  updated_at: string;
}

// Transformed entry for AI (standardized format)
export interface TransformedEntry {
  id: string;
  date: string;             // YYYY-MM-DD (normalized)
  title: string;            // Trimmed, max 100 chars
  content: string;          // Cleaned, normalized whitespace
  wordCount: number;        // Calculated
  charCount: number;        // Calculated
  isEmpty: boolean;         // text.trim() === ""
  metadata: {
    createdAt: string;      // ISO8601 (original)
    dayOfWeek: string;      // "Monday", "Tuesday", etc.
    timeOfDay: string;      // "morning", "afternoon", "evening", "night"
  };
}

// Response to client
export interface FetchJournalEntriesResponse {
  entries: TransformedEntry[];
  metadata: {
    totalCount: number;         // Total entries in date range
    returnedCount: number;      // Entries returned (may be limited)
    dateRangeStart: string;     // ISO8601
    dateRangeEnd: string;       // ISO8601
    oldestEntryDate: string;    // ISO8601
    newestEntryDate: string;    // ISO8601
    averageWordCount: number;
    totalWordCount: number;
  };
  cached: boolean;              // Was this from cache?
  generatedAt: string;          // ISO8601
}
```

### Transformation Logic (`fetch-journal-entries/transformer.ts`)

```typescript
import type { EntryRow, TransformedEntry } from './types.ts';

export function transformEntry(raw: EntryRow): TransformedEntry {
  const createdDate = new Date(raw.created_at);

  // Normalize title
  const title = raw.title
    .trim()
    .slice(0, 100) // Max 100 chars
    .replace(/\s+/g, ' '); // Collapse multiple spaces

  // Normalize content
  const content = raw.text
    .trim()
    .replace(/\r\n/g, '\n')     // Normalize line breaks
    .replace(/\n{3,}/g, '\n\n') // Max 2 consecutive line breaks
    .replace(/\s+$/gm, '');     // Remove trailing whitespace per line

  // Calculate metrics
  const wordCount = content
    .split(/\s+/)
    .filter(word => word.length > 0).length;

  const charCount = content.length;
  const isEmpty = content.length === 0;

  return {
    id: raw.id,
    date: formatDateYYYYMMDD(createdDate),
    title,
    content,
    wordCount,
    charCount,
    isEmpty,
    metadata: {
      createdAt: raw.created_at,
      dayOfWeek: getDayOfWeek(createdDate),
      timeOfDay: getTimeOfDay(createdDate),
    },
  };
}

export function formatDateYYYYMMDD(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function getDayOfWeek(date: Date): string {
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  return days[date.getDay()];
}

export function getTimeOfDay(date: Date): string {
  const hour = date.getHours();
  if (hour < 6) return 'night';
  if (hour < 12) return 'morning';
  if (hour < 18) return 'afternoon';
  if (hour < 22) return 'evening';
  return 'night';
}

export function calculateMetadata(entries: TransformedEntry[]) {
  const totalWordCount = entries.reduce((sum, e) => sum + e.wordCount, 0);
  const averageWordCount = entries.length > 0
    ? Math.round(totalWordCount / entries.length)
    : 0;

  const dates = entries
    .map(e => new Date(e.metadata.createdAt))
    .sort((a, b) => a.getTime() - b.getTime());

  return {
    totalWordCount,
    averageWordCount,
    oldestEntryDate: dates[0]?.toISOString() ?? new Date().toISOString(),
    newestEntryDate: dates[dates.length - 1]?.toISOString() ?? new Date().toISOString(),
  };
}
```

### Date Range Utils (`fetch-journal-entries/dateUtils.ts`)

```typescript
export function calculateDateRange(daysBack: number): { start: string; end: string } {
  const end = new Date();
  const start = new Date();
  start.setDate(start.getDate() - daysBack);

  // Set to start of day for consistent queries
  start.setHours(0, 0, 0, 0);
  end.setHours(23, 59, 59, 999);

  return {
    start: start.toISOString(),
    end: end.toISOString(),
  };
}

export function validateDaysBack(daysBack: number): number {
  // Clamp between 7 and 365 days
  if (daysBack < 7) return 7;
  if (daysBack > 365) return 365;
  return Math.floor(daysBack);
}

export function validateMaxEntries(maxEntries: number): number {
  // Clamp between 3 and 100
  if (maxEntries < 3) return 3;
  if (maxEntries > 100) return 100;
  return Math.floor(maxEntries);
}
```

### Main Handler (`fetch-journal-entries/index.ts`)

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { transformEntry, calculateMetadata } from './transformer.ts';
import { calculateDateRange, validateDaysBack, validateMaxEntries } from './dateUtils.ts';
import type {
  FetchJournalEntriesRequest,
  FetchJournalEntriesResponse,
  EntryRow,
} from './types.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 1. Authenticate user
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing Authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const token = authHeader.replace('Bearer ', '');
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Get user from token
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`✅ User authenticated: ${user.email}`);

    // 2. Parse request
    const body = await req.json() as FetchJournalEntriesRequest;
    const daysBack = validateDaysBack(body.daysBack ?? 30);
    const maxEntries = validateMaxEntries(body.maxEntries ?? 50);
    const includeEmpty = body.includeEmpty ?? false;

    console.log(`📊 Fetching entries: ${daysBack} days back, max ${maxEntries} entries`);

    // 3. Calculate date range
    const dateRange = calculateDateRange(daysBack);

    // 4. Fetch entries from Supabase
    let query = supabase
      .from('entries')
      .select('id, user_id, title, text, created_at, updated_at')
      .eq('user_id', user.id)
      .gte('created_at', dateRange.start)
      .lte('created_at', dateRange.end)
      .order('created_at', { ascending: false });

    // Fetch more than maxEntries so we can filter and still have enough
    query = query.limit(maxEntries * 2);

    const { data: rawEntries, error: fetchError } = await query;

    if (fetchError) {
      console.error('❌ Database error:', fetchError);
      return new Response(
        JSON.stringify({
          error: 'Failed to fetch entries',
          code: 'DB_ERROR',
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`✅ Fetched ${rawEntries?.length ?? 0} raw entries`);

    // 5. Transform entries
    let transformed = (rawEntries as EntryRow[]).map(transformEntry);

    // 6. Filter empty entries if needed
    if (!includeEmpty) {
      transformed = transformed.filter(e => !e.isEmpty);
    }

    // 7. Limit to maxEntries
    const totalCount = transformed.length;
    transformed = transformed.slice(0, maxEntries);

    console.log(`✅ Returning ${transformed.length} transformed entries (total: ${totalCount})`);

    // 8. Calculate metadata
    const metadata = calculateMetadata(transformed);

    // 9. Build response
    const response: FetchJournalEntriesResponse = {
      entries: transformed,
      metadata: {
        totalCount,
        returnedCount: transformed.length,
        dateRangeStart: dateRange.start,
        dateRangeEnd: dateRange.end,
        ...metadata,
      },
      cached: false,
      generatedAt: new Date().toISOString(),
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('❌ Unexpected error:', error);
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        code: 'INTERNAL_ERROR',
        details: error.message,
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
```

### Continuous Adaptation Strategy

**1. Schema Evolution**
```typescript
// Handle missing fields gracefully
export function transformEntryWithDefaults(raw: Partial<EntryRow>): TransformedEntry {
  return transformEntry({
    id: raw.id ?? crypto.randomUUID(),
    user_id: raw.user_id ?? '',
    title: raw.title ?? 'Untitled',
    text: raw.text ?? '',
    created_at: raw.created_at ?? new Date().toISOString(),
    updated_at: raw.updated_at ?? new Date().toISOString(),
  });
}
```

**2. Data Quality Monitoring**
```typescript
// Track data quality metrics
export interface DataQualityMetrics {
  emptyEntriesCount: number;
  shortEntriesCount: number;      // <50 words
  longEntriesCount: number;       // >1000 words
  missingTitlesCount: number;
  averageQualityScore: number;    // 0-100
}

export function calculateQualityMetrics(entries: TransformedEntry[]): DataQualityMetrics {
  const empty = entries.filter(e => e.isEmpty).length;
  const short = entries.filter(e => e.wordCount < 50 && !e.isEmpty).length;
  const long = entries.filter(e => e.wordCount > 1000).length;
  const missingTitles = entries.filter(e => e.title === 'Untitled').length;

  // Quality score: penalize empty, reward substantial entries
  const scores = entries.map(e => {
    if (e.isEmpty) return 0;
    if (e.wordCount < 20) return 30;
    if (e.wordCount < 50) return 50;
    if (e.wordCount < 100) return 70;
    if (e.wordCount < 300) return 90;
    return 100;
  });

  const averageQualityScore = scores.length > 0
    ? Math.round(scores.reduce((sum, s) => sum + s, 0) / scores.length)
    : 0;

  return {
    emptyEntriesCount: empty,
    shortEntriesCount: short,
    longEntriesCount: long,
    missingTitlesCount: missingTitles,
    averageQualityScore,
  };
}
```

**3. Caching Strategy**
```typescript
// Cache key: user_id + date_range + max_entries
function generateCacheKey(userId: string, daysBack: number, maxEntries: number): string {
  return `journal_entries:${userId}:${daysBack}:${maxEntries}`;
}

// Cache in Supabase (optional table: journal_entry_cache)
// - Invalidate when new entry created (trigger)
// - TTL: 1 hour (much shorter than insights cache)
```

---

## 2B. GENERATE-INSIGHTS EDGE FUNCTION (UPDATED)

### Purpose

Receives transformed journal entries from `fetch-journal-entries` (or directly from client) and generates AI-powered insights using OpenAI. Handles caching, token optimization, and validation.

### Updated Request Flow

**Option 1: Client calls both functions sequentially**
```
Client → fetch-journal-entries → get JSON → generate-insights → get insights
```

**Option 2: generate-insights calls fetch-journal-entries internally** (RECOMMENDED)
```
Client → generate-insights
           ↓
           fetch-journal-entries → get JSON
           ↓
           OpenAI API → get insights
           ↓
Client ← return insights
```

We'll use **Option 2** for simplicity - client only calls one function.

### Types & Interfaces (`types.ts`)

```typescript
// Import TransformedEntry from fetch-journal-entries
import type { TransformedEntry, FetchJournalEntriesResponse } from '../fetch-journal-entries/types.ts';
// Input from client
export interface GenerateInsightsRequest {
  forceRegenerate?: boolean; // Skip cache if true
  daysBack?: number;         // Default 30
}

// Entry as fetched from DB
export interface EntryRow {
  id: string;
  user_id: string;
  title: string;
  text: string;
  created_at: string;       // ISO8601
  updated_at: string;
}

// Transformed for OpenAI prompt
export interface EntryForPrompt {
  date: string;             // YYYY-MM-DD
  title: string;
  content: string;
  word_count: number;
  mood: string | null;
}

// Source entry in theme
export interface SourceEntry {
  date: string;             // YYYY-MM-DD
  title: string;
}

// Single theme
export interface Theme {
  name: string;             // 2-4 words
  icon: string;             // Single emoji
  explanation: string;      // ≤60 words
  frequency: string;        // e.g., "3 times this month"
  source_entries: SourceEntry[];
}

// OpenAI JSON response schema
export interface InsightResponse {
  summary: string;          // ≤140 chars
  description: string;      // 150-180 words
  themes: Theme[];          // 4-5 themes
}

// DB row for user_insights table
export interface InsightRecord {
  user_id: string;
  insight_type: string;     // 'theme_summary'
  content: InsightResponse; // JSONB
  entries_analyzed_count: number;
  date_range_start: string; // ISO8601
  date_range_end: string;   // ISO8601
  expires_at: string;       // ISO8601 (now + 7 days)
  model_version: string;    // 'gpt-4o'
  prompt_tokens?: number;
  completion_tokens?: number;
  generation_time_ms?: number;
}
```

### Prompt Builder (`prompts.ts`)

```typescript
export const SYSTEM_PROMPT = `You are a journaling companion who helps users see emotional patterns. Write warmly and directly; avoid clinical jargon and hedging. Reference concrete details (dates, activities, moods). Acknowledge struggle and growth without toxic positivity. Use second person. Never diagnose or prescribe. Return valid JSON only following the schema. Stay under 800 tokens.`;

export function buildInsightsPrompt(entries: EntryForPrompt[]): string {
  const entriesJSON = JSON.stringify(entries, null, 2);
  return `Generate insights from these journal entries using the exact schema above.

Entries:
${entriesJSON}

Requirements:
- summary: ≤140 chars, second person, emotional landscape overview
- description: 150-180 words, second person, references ≥2 entry titles
- themes: exactly 4-5 themes
  - name: 2-4 words, specific (not generic like "self-reflection")
  - icon: single emoji
  - explanation: ≤60 words, why this matters to the user
  - frequency: real count (e.g., "2 times this month", "appeared in 5 entries")
  - source_entries: array of objects with both date and title

Return valid JSON only. No markdown. Total <750 tokens.`;
}

export const OPENAI_RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    summary: { type: "string", maxLength: 140 },
    description: { type: "string" },
    themes: {
      type: "array",
      minItems: 4,
      maxItems: 5,
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          icon: { type: "string" },
          explanation: { type: "string" },
          frequency: { type: "string" },
          source_entries: {
            type: "array",
            items: {
              type: "object",
              properties: {
                date: { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" },
                title: { type: "string" }
              },
              required: ["date", "title"]
            }
          }
        },
        required: ["name", "icon", "explanation", "frequency", "source_entries"]
      }
    }
  },
  required: ["summary", "description", "themes"]
};
```

### Validation (`validation.ts`)

```typescript
import { InsightResponse, Theme } from './types.ts';

export class ValidationError extends Error {
  constructor(message: string, public field?: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

export function validateInsightStructure(resp: unknown): InsightResponse {
  if (!resp || typeof resp !== 'object') {
    throw new ValidationError('Response must be an object');
  }

  const obj = resp as Record<string, unknown>;

  // Validate summary
  if (typeof obj.summary !== 'string') {
    throw new ValidationError('summary must be a string', 'summary');
  }
  if (obj.summary.length === 0 || obj.summary.length > 140) {
    throw new ValidationError('summary must be 1-140 chars', 'summary');
  }

  // Validate description
  if (typeof obj.description !== 'string') {
    throw new ValidationError('description must be a string', 'description');
  }
  if (obj.description.length < 50) {
    throw new ValidationError('description too short (min 50 chars)', 'description');
  }

  // Validate themes
  if (!Array.isArray(obj.themes)) {
    throw new ValidationError('themes must be an array', 'themes');
  }
  if (obj.themes.length < 4 || obj.themes.length > 5) {
    throw new ValidationError('themes must contain 4-5 items', 'themes');
  }

  // Validate each theme
  obj.themes.forEach((theme, idx) => {
    if (!theme || typeof theme !== 'object') {
      throw new ValidationError(`themes[${idx}] must be an object`, `themes[${idx}]`);
    }
    const t = theme as Record<string, unknown>;

    if (typeof t.name !== 'string' || !t.name) {
      throw new ValidationError(`themes[${idx}].name required`, `themes[${idx}].name`);
    }
    if (typeof t.icon !== 'string' || !t.icon) {
      throw new ValidationError(`themes[${idx}].icon required`, `themes[${idx}].icon`);
    }
    if (typeof t.explanation !== 'string' || !t.explanation) {
      throw new ValidationError(`themes[${idx}].explanation required`, `themes[${idx}].explanation`);
    }
    if (typeof t.frequency !== 'string' || !t.frequency) {
      throw new ValidationError(`themes[${idx}].frequency required`, `themes[${idx}].frequency`);
    }
    if (!Array.isArray(t.source_entries) || t.source_entries.length === 0) {
      throw new ValidationError(`themes[${idx}].source_entries must be non-empty array`, `themes[${idx}].source_entries`);
    }

    // Validate source_entries
    t.source_entries.forEach((entry: unknown, entryIdx) => {
      if (!entry || typeof entry !== 'object') {
        throw new ValidationError(`themes[${idx}].source_entries[${entryIdx}] must be object`, `themes[${idx}].source_entries[${entryIdx}]`);
      }
      const e = entry as Record<string, unknown>;
      if (typeof e.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(e.date)) {
        throw new ValidationError(`themes[${idx}].source_entries[${entryIdx}].date must be YYYY-MM-DD`, `themes[${idx}].source_entries[${entryIdx}].date`);
      }
      if (typeof e.title !== 'string' || !e.title) {
        throw new ValidationError(`themes[${idx}].source_entries[${entryIdx}].title required`, `themes[${idx}].source_entries[${entryIdx}].title`);
      }
    });
  });

  return obj as InsightResponse;
}
```

### Caching Functions

```typescript
// In index.ts

async function checkInsightsCache(
  supabaseClient: SupabaseClient,
  userId: string,
  dateRangeStart: string,
  dateRangeEnd: string
): Promise<InsightResponse | null> {
  const { data, error } = await supabaseClient
    .from('user_insights')
    .select('content, generated_at')
    .eq('user_id', userId)
    .eq('insight_type', 'theme_summary')
    .eq('is_valid', true)
    .eq('date_range_start', dateRangeStart)
    .eq('date_range_end', dateRangeEnd)
    .gt('expires_at', new Date().toISOString())
    .order('generated_at', { ascending: false })
    .limit(1)
    .single();

  if (error || !data) return null;

  console.log('✅ Cache hit:', data.generated_at);
  return data.content as InsightResponse;
}

async function writeInsightsCache(
  supabaseClient: SupabaseClient,
  record: InsightRecord
): Promise<void> {
  const { error } = await supabaseClient
    .from('user_insights')
    .insert(record);

  if (error) {
    console.error('❌ Cache write failed:', error);
    throw new Error(`Failed to cache insights: ${error.message}`);
  }

  console.log('✅ Insights cached successfully');
}
```

### Token Optimization Strategy

**Goal:** Cap total tokens at 2000 (input + output) while maintaining quality

**Token Budget Breakdown:**
- System prompt: ~150 tokens
- User prompt template: ~100 tokens
- Entry data: ~1000-1200 tokens (optimized)
- Response: ~600 tokens
- **Total: ~1950 tokens** (50 token buffer)

#### Input Optimization (`tokenOptimizer.ts`)

```typescript
export interface TokenBudget {
  systemPrompt: number;      // 150
  userPromptTemplate: number; // 100
  entries: number;            // 1200 max
  response: number;           // 600 estimated
  buffer: number;             // 50
}

export const TOKEN_BUDGET: TokenBudget = {
  systemPrompt: 150,
  userPromptTemplate: 100,
  entries: 1200,
  response: 600,
  buffer: 50,
};

export const MAX_TOTAL_TOKENS = 2000;

// Rough token estimation (1 token ≈ 4 characters)
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

export function optimizeEntriesForTokens(
  entries: EntryForPrompt[],
  maxTokens: number = TOKEN_BUDGET.entries
): EntryForPrompt[] {
  // Strategy 1: Limit number of entries (max 20)
  let optimized = entries.slice(0, 20);

  // Strategy 2: Truncate long entries
  optimized = optimized.map(entry => ({
    ...entry,
    content: truncateContent(entry.content, 300), // Max 300 chars per entry
    title: entry.title.slice(0, 60), // Max 60 chars per title
  }));

  // Strategy 3: Check total and remove oldest if still over budget
  let totalTokens = estimateTokens(JSON.stringify(optimized));
  while (totalTokens > maxTokens && optimized.length > 3) {
    optimized = optimized.slice(0, -1); // Remove oldest entry
    totalTokens = estimateTokens(JSON.stringify(optimized));
  }

  console.log(`📊 Token optimization: ${entries.length} entries → ${optimized.length} entries (~${totalTokens} tokens)`);

  return optimized;
}

function truncateContent(content: string, maxChars: number): string {
  if (content.length <= maxChars) return content;

  // Try to truncate at sentence boundary
  const truncated = content.slice(0, maxChars);
  const lastPeriod = truncated.lastIndexOf('.');
  const lastQuestion = truncated.lastIndexOf('?');
  const lastExclamation = truncated.lastIndexOf('!');

  const lastSentenceEnd = Math.max(lastPeriod, lastQuestion, lastExclamation);

  if (lastSentenceEnd > maxChars * 0.7) {
    // Good sentence boundary found
    return truncated.slice(0, lastSentenceEnd + 1);
  }

  // No good boundary, truncate at word
  const lastSpace = truncated.lastIndexOf(' ');
  return truncated.slice(0, lastSpace) + '...';
}
```

#### Optimized Prompts

**Compact System Prompt** (~150 tokens)

```typescript
export const SYSTEM_PROMPT_OPTIMIZED = `You're a journaling companion analyzing emotional patterns. Write warmly in second person. Reference concrete details (dates, activities). Acknowledge struggle and growth naturally. No clinical terms, diagnoses, or hedging. Return valid JSON only per schema. Stay under 600 output tokens.`;
```

**Compact User Prompt** (~100 tokens + entry data)

```typescript
export function buildInsightsPromptOptimized(entries: EntryForPrompt[]): string {
  const entriesJSON = JSON.stringify(entries);
  return `Analyze these journal entries. Return JSON with:
- summary: ≤140 chars, emotional overview, 2nd person
- description: 150-180 words, references ≥2 entry titles, 2nd person
- themes: exactly 4-5 items
  - name: 2-4 words
  - icon: emoji
  - explanation: ≤60 words
  - frequency: real count (e.g. "3 times")
  - source_entries: [{date,title}]

Entries: ${entriesJSON}

Return only valid JSON, no markdown.`;
}
```

#### Output Constraints

Update OpenAI call with strict token limits:

```typescript
const completion = await openaiClient.chat.completions.create({
  model: 'gpt-4o',
  messages: [
    { role: 'system', content: SYSTEM_PROMPT_OPTIMIZED },
    { role: 'user', content: buildInsightsPromptOptimized(optimizedEntries) }
  ],
  response_format: { type: 'json_object' },
  temperature: 0.7,
  max_tokens: 700, // Cap output at 700 tokens (buffer for 600 target)
});
```

#### Token Tracking

```typescript
interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  withinBudget: boolean;
}

function trackTokenUsage(completion: OpenAI.ChatCompletion): TokenUsage {
  const usage = completion.usage!;
  const total = usage.prompt_tokens + usage.completion_tokens;
  const withinBudget = total <= MAX_TOTAL_TOKENS;

  console.log(`📊 Token usage: ${usage.prompt_tokens} in + ${usage.completion_tokens} out = ${total} total`);

  if (!withinBudget) {
    console.warn(`⚠️ Over budget! ${total}/${MAX_TOTAL_TOKENS} tokens`);
  }

  return {
    promptTokens: usage.prompt_tokens,
    completionTokens: usage.completion_tokens,
    totalTokens: total,
    withinBudget,
  };
}
```

### OpenAI Call (JSON Mode with Token Optimization)

```typescript
import OpenAI from 'npm:openai@4';
import { SYSTEM_PROMPT_OPTIMIZED, buildInsightsPromptOptimized } from './prompts.ts';
import { validateInsightStructure } from './validation.ts';
import { optimizeEntriesForTokens, trackTokenUsage, MAX_TOTAL_TOKENS } from './tokenOptimizer.ts';
import type { EntryForPrompt, InsightResponse } from './types.ts';

async function generateInsightsWithOpenAI(
  openaiClient: OpenAI,
  entries: EntryForPrompt[]
): Promise<{
  insights: InsightResponse;
  tokens: { prompt: number; completion: number; total: number; withinBudget: boolean }
}> {
  const startTime = Date.now();

  // Optimize entries to stay within token budget
  const optimizedEntries = optimizeEntriesForTokens(entries);
  console.log(`🤖 Calling OpenAI with ${optimizedEntries.length} entries...`);

  const completion = await openaiClient.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      { role: 'system', content: SYSTEM_PROMPT_OPTIMIZED },
      { role: 'user', content: buildInsightsPromptOptimized(optimizedEntries) }
    ],
    response_format: { type: 'json_object' },
    temperature: 0.7,
    max_tokens: 700, // Cap output tokens
  });

  const elapsed = Date.now() - startTime;
  const tokenUsage = trackTokenUsage(completion);

  console.log(`✅ OpenAI responded in ${elapsed}ms`);

  // Log warning if over budget (but don't fail)
  if (!tokenUsage.withinBudget) {
    console.warn(`⚠️ Token budget exceeded: ${tokenUsage.totalTokens}/${MAX_TOTAL_TOKENS}`);
  }

  const content = completion.choices[0]?.message?.content;
  if (!content) {
    throw new Error('OpenAI returned empty response');
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (e) {
    throw new Error(`OpenAI returned invalid JSON: ${e.message}`);
  }

  const insights = validateInsightStructure(parsed);

  return {
    insights,
    tokens: {
      prompt: tokenUsage.promptTokens,
      completion: tokenUsage.completionTokens,
      total: tokenUsage.totalTokens,
      withinBudget: tokenUsage.withinBudget,
    },
  };
}
```

### Error Matrix

| Scenario | HTTP Code | Message | Client Action |
|----------|-----------|---------|---------------|
| Not authenticated | 401 | "Authentication required. Please sign in." | Redirect to login |
| OpenAI API key missing | 500 | "Service configuration error. Please contact support." | Show error, log to console |
| Fewer than 3 entries | 400 | "You need at least 3 journal entries to generate insights." | Show empty state with CTA |
| OpenAI API error | 502 | "AI service unavailable. Please try again later." | Show retry button |
| OpenAI timeout (>30s) | 504 | "Request timed out. Please try again." | Show retry button |
| Validation error | 422 | "Generated insights were invalid. Please try again." | Show retry button, log details |
| Database error (fetch) | 500 | "Failed to load entries. Please try again." | Show retry button |
| Database error (cache write) | 200 | *Return insights anyway, log warning* | Display insights |
| Rate limit (if implemented) | 429 | "You've reached the hourly limit. Try again in {X} minutes." | Show countdown timer |
| Generic error | 500 | "Something went wrong. Please try again." | Show retry button |

### Error Response Format

```typescript
interface ErrorResponse {
  error: string;           // User-facing message
  code: string;            // Machine-readable code (e.g., 'INSUFFICIENT_ENTRIES')
  details?: string;        // Additional context (not shown to user)
}
```

### Sequence (Implementation Checklist)

#### Phase 1: Fetch-Journal-Entries Function

1. ✅ Create `functions/fetch-journal-entries/types.ts`
   - [ ] FetchJournalEntriesRequest
   - [ ] EntryRow
   - [ ] TransformedEntry
   - [ ] FetchJournalEntriesResponse
   - [ ] DataQualityMetrics

2. ✅ Create `functions/fetch-journal-entries/transformer.ts`
   - [ ] transformEntry(raw: EntryRow): TransformedEntry
   - [ ] formatDateYYYYMMDD(date: Date): string
   - [ ] getDayOfWeek(date: Date): string
   - [ ] getTimeOfDay(date: Date): string
   - [ ] calculateMetadata(entries: TransformedEntry[])
   - [ ] calculateQualityMetrics(entries: TransformedEntry[])
   - [ ] transformEntryWithDefaults(raw: Partial<EntryRow>)

3. ✅ Create `functions/fetch-journal-entries/dateUtils.ts`
   - [ ] calculateDateRange(daysBack: number)
   - [ ] validateDaysBack(daysBack: number)
   - [ ] validateMaxEntries(maxEntries: number)

4. ✅ Create `functions/fetch-journal-entries/index.ts`
   - [ ] Import dependencies (serve, Supabase client)
   - [ ] Handle CORS preflight
   - [ ] Authenticate user from Authorization header
   - [ ] Parse request body (daysBack, maxEntries, includeEmpty)
   - [ ] Calculate date range
   - [ ] Query entries from Supabase (with RLS)
   - [ ] Transform entries using transformer
   - [ ] Filter empty entries if needed
   - [ ] Limit to maxEntries
   - [ ] Calculate metadata
   - [ ] Return JSON response
   - [ ] Handle errors (401, 500)

5. ✅ Test fetch-journal-entries locally
   - [ ] `supabase functions serve fetch-journal-entries`
   - [ ] Test with curl (various daysBack, maxEntries)
   - [ ] Verify transformation (dates, word counts)
   - [ ] Test with empty entries
   - [ ] Test error cases (no auth, no entries)

6. ✅ Deploy fetch-journal-entries
   - [ ] `supabase functions deploy fetch-journal-entries`
   - [ ] Test production endpoint
   - [ ] Monitor logs

#### Phase 2: Generate-Insights Function

7. ✅ Create `functions/generate-insights/types.ts`
   - [ ] Import TransformedEntry from fetch-journal-entries
   - [ ] GenerateInsightsRequest
   - [ ] SourceEntry, Theme, InsightResponse
   - [ ] InsightRecord

8. ✅ Create `functions/generate-insights/tokenOptimizer.ts`
   - [ ] TokenBudget interface
   - [ ] estimateTokens(text: string): number
   - [ ] optimizeEntriesForTokens(entries, maxTokens)
   - [ ] truncateContent(content, maxChars)
   - [ ] trackTokenUsage(completion)

9. ✅ Create `functions/generate-insights/prompts.ts`
   - [ ] SYSTEM_PROMPT_OPTIMIZED (~150 tokens)
   - [ ] buildInsightsPromptOptimized(entries) (~100 tokens + entries)
   - [ ] OPENAI_RESPONSE_SCHEMA

10. ✅ Create `functions/generate-insights/validation.ts`
    - [ ] ValidationError class
    - [ ] validateInsightStructure(resp)
    - [ ] Validate summary (1-140 chars)
    - [ ] Validate description (50+ chars)
    - [ ] Validate themes (4-5 items)
    - [ ] Validate source_entries

11. ✅ Create `functions/generate-insights/index.ts`
    - [ ] Import dependencies (serve, Supabase, OpenAI)
    - [ ] Initialize OpenAI client with OPENAI_API_KEY
    - [ ] Handle CORS preflight
    - [ ] Authenticate user
    - [ ] Parse request (forceRegenerate, daysBack)
    - [ ] **Call fetch-journal-entries function internally**
    - [ ] Check if <3 entries, return 400
    - [ ] If !forceRegenerate, check cache (user_insights table)
    - [ ] If cache hit, return cached insights
    - [ ] Optimize entries for token budget (~1200 tokens)
    - [ ] Call OpenAI with optimized prompt (max 700 output tokens)
    - [ ] Track token usage, log warning if over 2000 total
    - [ ] Validate OpenAI response
    - [ ] Write to cache (non-blocking, 7-day expiry)
    - [ ] Return insights with token metadata
    - [ ] Handle errors (timeout, validation, OpenAI API)

12. ✅ Create integration helper for calling fetch-journal-entries
    - [ ] `async function fetchTransformedEntries(token, daysBack, maxEntries)`
    - [ ] Call via HTTP to fetch-journal-entries function
    - [ ] Parse FetchJournalEntriesResponse
    - [ ] Return TransformedEntry[]

13. ✅ Test generate-insights locally
    - [ ] `supabase functions serve generate-insights`
    - [ ] Test with sufficient entries (3+)
    - [ ] Verify token optimization (<2000 total)
    - [ ] Test cache hit/miss
    - [ ] Test forceRegenerate
    - [ ] Test error cases (no entries, OpenAI error)

14. ✅ Deploy both functions
    - [ ] `supabase functions deploy fetch-journal-entries`
    - [ ] `supabase functions deploy generate-insights`
    - [ ] Set secrets: `supabase secrets set OPENAI_API_KEY=sk-...`

15. ✅ End-to-end testing
    - [ ] Test full flow: client → generate-insights → fetch-journal-entries → OpenAI
    - [ ] Verify insights structure (summary, description, 4-5 themes)
    - [ ] Test cache invalidation (create new entry → cache should be invalid)
    - [ ] Test token budget adherence (check logs for warnings)
    - [ ] Test pull-to-refresh (forceRegenerate=true)

16. ✅ Monitor logs
    - [ ] `supabase functions logs fetch-journal-entries --tail`
    - [ ] `supabase functions logs generate-insights --tail`
    - [ ] Check token usage per request
    - [ ] Check cache hit rate

---

## 3. FRONTEND PLAN

### File Tree

```
withMemento/
├── Models/
│   ├── Insight.swift                  [MODIFY] Complete model
│   ├── Theme.swift                    [CREATE] Theme model
│   └── SourceEntry.swift              [CREATE] Source entry model
├── Services/
│   └── InsightsService.swift          [CREATE] API wrapper
├── ViewModels/
│   └── InsightViewModel.swift         [MODIFY] Complete logic
├── Views/
│   └── Insights/
│       ├── InsightsView.swift         [MODIFY] Connect to real data
│       └── ThemeDetailView.swift      [CREATE] Theme drill-down (optional v2)
└── Components/
    ├── Cards/
    │   ├── AISummarySection.swift     [EXISTS] Already built
    │   └── InsightCard.swift          [EXISTS] Already built
    └── Tags/
        └── InsightsThemesSection.swift [MODIFY] Support Theme model
```

### Swift Models with CodingKeys

**`Models/SourceEntry.swift`**

```swift
import Foundation

public struct SourceEntry: Codable, Hashable, Identifiable {
    public let id: UUID = UUID() // Local only, not from API
    public let date: String      // YYYY-MM-DD
    public let title: String

    enum CodingKeys: String, CodingKey {
        case date
        case title
    }

    public init(date: String, title: String) {
        self.date = date
        self.title = title
    }

    /// Formatted date for display (e.g., "Jan 15, 2024")
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: date) else { return date }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d, yyyy"
        return displayFormatter.string(from: date)
    }
}
```

**`Models/Theme.swift`**

```swift
import Foundation

public struct Theme: Codable, Hashable, Identifiable {
    public let id: UUID = UUID() // Local only, not from API
    public let name: String
    public let icon: String
    public let explanation: String
    public let frequency: String
    public let sourceEntries: [SourceEntry]

    enum CodingKeys: String, CodingKey {
        case name
        case icon
        case explanation
        case frequency
        case sourceEntries = "source_entries"
    }

    public init(name: String, icon: String, explanation: String, frequency: String, sourceEntries: [SourceEntry]) {
        self.name = name
        self.icon = icon
        self.explanation = explanation
        self.frequency = frequency
        self.sourceEntries = sourceEntries
    }
}
```

**`Models/Insight.swift`**

```swift
import Foundation

public struct Insight: Codable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let summary: String
    public let description: String
    public let themes: [Theme]

    // Metadata
    public let entriesAnalyzedCount: Int
    public let dateRangeStart: Date
    public let dateRangeEnd: Date
    public let generatedAt: Date
    public let expiresAt: Date?
    public let modelVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case summary
        case description
        case themes
        case entriesAnalyzedCount = "entries_analyzed_count"
        case dateRangeStart = "date_range_start"
        case dateRangeEnd = "date_range_end"
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
        case modelVersion = "model_version"
    }

    public init(
        id: UUID = UUID(),
        userId: UUID,
        summary: String,
        description: String,
        themes: [Theme],
        entriesAnalyzedCount: Int,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        generatedAt: Date,
        expiresAt: Date? = nil,
        modelVersion: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.summary = summary
        self.description = description
        self.themes = themes
        self.entriesAnalyzedCount = entriesAnalyzedCount
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.modelVersion = modelVersion
    }

    /// Formatted date range for display
    public var dateRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: dateRangeStart)
        let end = formatter.string(from: dateRangeEnd)
        return "\(start) – \(end)"
    }

    /// Cache status
    public var isCached: Bool {
        guard let expires = expiresAt else { return false }
        return expires > Date()
    }
}

// MARK: - API Response Models (internal)

/// Response from generate-insights Edge Function
struct InsightAPIResponse: Codable {
    let summary: String
    let description: String
    let themes: [Theme]

    // Metadata fields from user_insights table
    let id: UUID?
    let userId: UUID?
    let entriesAnalyzedCount: Int?
    let dateRangeStart: String?
    let dateRangeEnd: String?
    let generatedAt: String?
    let expiresAt: String?
    let modelVersion: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case themes
        case id
        case userId = "user_id"
        case entriesAnalyzedCount = "entries_analyzed_count"
        case dateRangeStart = "date_range_start"
        case dateRangeEnd = "date_range_end"
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
        case modelVersion = "model_version"
    }
}
```

### InsightsService API

**`Services/InsightsService.swift`**

```swift
import Foundation
import Supabase

final class InsightsService {
    static let shared = InsightsService()

    private init() {}

    private var supabase: SupabaseClient? {
        SupabaseService.shared.supabase
    }

    /// Fetches or generates insights for the current user
    /// - Parameters:
    ///   - forceRegenerate: Skip cache and generate fresh insights
    ///   - daysBack: Number of days to analyze (default 30)
    /// - Returns: Insight object with themes
    func fetchInsights(forceRegenerate: Bool = false, daysBack: Int = 30) async throws -> Insight {
        guard let supabase else {
            throw InsightsServiceError.clientNotConfigured
        }

        // Get auth token
        let session = try await supabase.auth.session
        let token = session.accessToken

        // Call Edge Function
        let body: [String: Any] = [
            "forceRegenerate": forceRegenerate,
            "daysBack": daysBack
        ]

        let response = try await supabase.functions.invoke(
            "generate-insights",
            options: FunctionInvokeOptions(
                body: body
            )
        )

        // Parse response
        guard let data = response.data else {
            throw InsightsServiceError.emptyResponse
        }

        let apiResponse = try JSONDecoder.iso8601.decode(InsightAPIResponse.self, from: data)

        // Transform to Insight model
        return Insight(
            id: apiResponse.id ?? UUID(),
            userId: apiResponse.userId ?? session.user.id,
            summary: apiResponse.summary,
            description: apiResponse.description,
            themes: apiResponse.themes,
            entriesAnalyzedCount: apiResponse.entriesAnalyzedCount ?? 0,
            dateRangeStart: apiResponse.dateRangeStart?.iso8601Date ?? Date(),
            dateRangeEnd: apiResponse.dateRangeEnd?.iso8601Date ?? Date(),
            generatedAt: apiResponse.generatedAt?.iso8601Date ?? Date(),
            expiresAt: apiResponse.expiresAt?.iso8601Date,
            modelVersion: apiResponse.modelVersion
        )
    }
}

// MARK: - Errors

enum InsightsServiceError: LocalizedError {
    case clientNotConfigured
    case emptyResponse
    case insufficientEntries
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .clientNotConfigured:
            return "Service not configured. Please sign in."
        case .emptyResponse:
            return "Received empty response from server."
        case .insufficientEntries:
            return "You need at least 3 journal entries to generate insights."
        case .serviceUnavailable:
            return "AI service unavailable. Please try again later."
        }
    }
}

// MARK: - Helpers

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension String {
    var iso8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: self)
    }
}
```

### ViewModel API

**`ViewModels/InsightViewModel.swift`**

```swift
import Foundation
import SwiftUI

@MainActor
class InsightViewModel: ObservableObject {
    @Published var insight: Insight?
    @Published var state: InsightState = .idle

    private let insightsService = InsightsService.shared
    private var hasLoadedOnce = false

    /// Loads insights once when view appears
    func loadInsightsIfNeeded() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        await loadInsights(forceRegenerate: false)
    }

    /// Loads or generates insights
    /// - Parameter forceRegenerate: Skip cache and generate fresh
    func loadInsights(forceRegenerate: Bool) async {
        // Prevent duplicate loads
        guard state != .loading && state != .regenerating else { return }

        state = forceRegenerate ? .regenerating : .loading

        do {
            insight = try await insightsService.fetchInsights(
                forceRegenerate: forceRegenerate,
                daysBack: 30
            )
            state = insight?.isCached == true ? .cached : .success
        } catch let error as InsightsServiceError {
            state = .error(error.localizedDescription ?? "Unknown error")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Pull-to-refresh action
    func refresh() async {
        await loadInsights(forceRegenerate: true)
    }
}

// MARK: - State

enum InsightState: Equatable {
    case idle           // Not loaded yet
    case loading        // First load
    case regenerating   // Force regenerate (pull-to-refresh)
    case success        // Fresh insights
    case cached         // Cached insights
    case error(String)  // Error message
    case empty          // <3 entries

    var isLoading: Bool {
        self == .loading || self == .regenerating
    }

    var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}
```

### States and Exact UI

| State | UI Display | User Action |
|-------|------------|-------------|
| `.idle` | Show skeleton/placeholder | Auto-load on appear |
| `.loading` | Show loading spinner + "Generating insights..." | None (wait) |
| `.regenerating` | Show loading overlay + "Regenerating..." | None (wait) |
| `.success` | Show AISummarySection + InsightsThemesSection | Pull-to-refresh to regenerate |
| `.cached` | Show insights + "Updated {date}" subtitle | Pull-to-refresh to regenerate |
| `.error(msg)` | Show error icon + message + "Try Again" button | Tap button to retry |
| `.empty` | Show empty state: "You need at least 3 entries" + "Start Journaling" button | Navigate to Journal tab |

**Loading View**

```swift
private var loadingView: some View {
    VStack(spacing: 16) {
        ProgressView()
            .tint(.white)
        Text(state == .regenerating ? "Regenerating insights..." : "Generating insights...")
            .font(type.body)
            .foregroundStyle(.white.opacity(0.8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

**Error View**

```swift
private var errorView: some View {
    VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 36))
            .foregroundStyle(.white)

        Text(state.errorMessage ?? "Something went wrong")
            .font(type.body)
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)

        Button("Try Again") {
            Task { await viewModel.loadInsights(forceRegenerate: false) }
        }
        .buttonStyle(PrimaryButtonStyle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 32)
}
```

**Empty State**

```swift
private var emptyStateView: some View {
    VStack(spacing: 16) {
        Image(systemName: "sparkles")
            .font(.system(size: 36))
            .foregroundStyle(.white)

        Text("You need at least 3 entries")
            .font(type.h3)
            .foregroundStyle(.white)

        Text("Start journaling to unlock insights about your emotional patterns.")
            .font(type.body)
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)

        Button("Start Journaling") {
            // Switch to Journal tab
        }
        .buttonStyle(PrimaryButtonStyle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 32)
}
```

### Navigation Integration

**`Views/Insights/InsightsView.swift`** (Modified)

```swift
public struct InsightsView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @StateObject private var insightViewModel = InsightViewModel()
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init() {}

    public var body: some View {
        Group {
            switch insightViewModel.state {
            case .idle, .loading:
                loadingView
            case .regenerating:
                loadingOverlay
            case .success, .cached:
                insightsContent
            case .error:
                errorView
            case .empty:
                emptyStateView
            }
        }
        .background(Color.clear)
        .ignoresSafeArea()
        .refreshable {
            await insightViewModel.refresh()
        }
        .task {
            await insightViewModel.loadInsightsIfNeeded()
        }
    }

    private var insightsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if let insight = insightViewModel.insight {
                    // AI Summary Section
                    AISummarySection(
                        title: insight.summary,
                        body: insight.description
                    )

                    // Themes Section
                    InsightsThemesSection(themes: insight.themes)

                    // Cache indicator (if cached)
                    if insight.isCached {
                        Text("Updated \(insight.generatedAt.relativeFormatted)")
                            .font(type.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 108)
            .padding(.bottom, 24)
        }
    }

    // ... (loadingView, errorView, emptyStateView as above)
}
```

### Testing Plan

**Unit Tests**

1. **SourceEntry**
   - Test formattedDate with valid date
   - Test formattedDate with invalid date (should return original)

2. **Theme**
   - Test CodingKeys mapping (source_entries → sourceEntries)
   - Test JSON decoding from API response

3. **Insight**
   - Test dateRangeFormatted output
   - Test isCached (expired vs valid)
   - Test JSON decoding from API response

4. **InsightsService**
   - Mock fetchInsights with cached response
   - Mock fetchInsights with fresh response
   - Mock error responses (401, 400, 500)

5. **InsightViewModel**
   - Test state transitions: idle → loading → success
   - Test error state on service failure
   - Test forceRegenerate skips cache
   - Test hasLoadedOnce prevents duplicate loads

**Manual Checklist**

- [ ] Empty state: Sign in with <3 entries → shows empty state
- [ ] First load: User with 3+ entries → shows loading → displays insights
- [ ] Pull-to-refresh: Swipe down → shows regenerating → updates insights
- [ ] Cached indicator: Second load shows "Updated X minutes ago"
- [ ] Error handling: Turn off WiFi → shows error + retry button
- [ ] Theme display: All 4-5 themes render with emojis
- [ ] Source entries: Tap theme (v2) → shows source entry list
- [ ] Navigation: Tab between Journal/Insights → state persists
- [ ] Sign out: Sign out → clear cached insights

---

## 4. DATABASE PLAN

### Migration SQL

**File:** `migrations/20251023100000_update_insights_schema.sql`

```sql
-- ============================================================
-- Migration: Update Insights Schema for AI Insights Feature
-- Date: 2025-10-23
-- Purpose: Add summary/description columns to existing user_insights table
-- ============================================================

-- Add summary and description columns
ALTER TABLE user_insights
  ADD COLUMN IF NOT EXISTS summary text,
  ADD COLUMN IF NOT EXISTS description text;

-- Update constraints to require summary/description for theme_summary type
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS theme_summary_requires_fields;

ALTER TABLE user_insights
  ADD CONSTRAINT theme_summary_requires_fields
    CHECK (
      (insight_type != 'theme_summary') OR
      (summary IS NOT NULL AND description IS NOT NULL)
    );

-- Add comment
COMMENT ON COLUMN user_insights.summary IS '≤140 char summary for theme_summary insights';
COMMENT ON COLUMN user_insights.description IS '150-180 word description for theme_summary insights';

-- Validation
DO $$
BEGIN
  RAISE NOTICE '✅ Insights schema updated successfully';
  RAISE NOTICE '   - Added: summary, description columns';
  RAISE NOTICE '   - Added: theme_summary_requires_fields constraint';
END $$;
```

### Rollback SQL

```sql
-- ============================================================
-- Rollback: Update Insights Schema
-- ============================================================

-- Drop constraint
ALTER TABLE user_insights
  DROP CONSTRAINT IF EXISTS theme_summary_requires_fields;

-- Drop columns
ALTER TABLE user_insights
  DROP COLUMN IF EXISTS summary,
  DROP COLUMN IF EXISTS description;

-- Verification
DO $$
BEGIN
  RAISE NOTICE '✅ Insights schema rollback complete';
END $$;
```

### Post-Migration Verification

```sql
-- 1. Check columns exist
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'user_insights'
  AND column_name IN ('summary', 'description')
ORDER BY column_name;

-- Expected:
-- summary     | text | YES
-- description | text | YES

-- 2. Check constraint exists
SELECT constraint_name, check_clause
FROM information_schema.check_constraints
WHERE constraint_name = 'theme_summary_requires_fields';

-- Expected: 1 row with CHECK clause

-- 3. Test insert (should succeed)
INSERT INTO user_insights (
  user_id,
  insight_type,
  content,
  summary,
  description,
  entries_analyzed_count,
  date_range_start,
  date_range_end,
  expires_at
) VALUES (
  auth.uid(),
  'theme_summary',
  '{"themes": []}'::jsonb,
  'Test summary',
  'Test description',
  5,
  now() - interval '30 days',
  now(),
  now() + interval '7 days'
);

-- Clean up test
DELETE FROM user_insights WHERE summary = 'Test summary';

-- 4. Test constraint (should fail)
INSERT INTO user_insights (
  user_id,
  insight_type,
  content,
  entries_analyzed_count
) VALUES (
  auth.uid(),
  'theme_summary',
  '{"themes": []}'::jsonb,
  0
);
-- Expected: ERROR: new row violates check constraint "theme_summary_requires_fields"
```

---

## 5. INTEGRATION & TESTING

### End-to-End Scenarios

**Scenario 1: Happy Path (New User)**

1. User signs up and creates account
2. User writes 3 journal entries over 3 days
3. User navigates to Insights tab
4. System shows loading spinner
5. Backend fetches 3 entries, calls OpenAI
6. System displays insights with 4 themes
7. User pulls to refresh
8. System shows "Regenerating..." overlay
9. System generates fresh insights (new themes)
10. User sees updated insights

**Scenario 2: Cached Insights**

1. User opens app (previously generated insights)
2. User navigates to Insights tab
3. System checks cache (valid for 6 more days)
4. System displays cached insights instantly (<100ms)
5. System shows "Updated 12 hours ago" subtitle
6. User pulls to refresh
7. System bypasses cache, calls OpenAI
8. System displays fresh insights

**Scenario 3: Insufficient Entries**

1. New user signs up
2. User writes 2 journal entries
3. User navigates to Insights tab
4. System shows loading spinner
5. Backend returns 400 error
6. System displays empty state: "You need at least 3 entries"
7. User taps "Start Journaling" button
8. System navigates to Journal tab

**Scenario 4: OpenAI Error**

1. User navigates to Insights tab (OpenAI API down)
2. System shows loading spinner
3. Backend calls OpenAI, times out after 30s
4. System displays error: "AI service unavailable"
5. User taps "Try Again"
6. System retries (OpenAI now available)
7. System displays insights

**Scenario 5: Offline Mode**

1. User opens app (no internet connection)
2. User navigates to Insights tab
3. System attempts to fetch insights
4. Request fails immediately (no network)
5. System displays error: "No internet connection"
6. User connects to WiFi
7. User taps "Try Again"
8. System successfully fetches insights

### Performance Targets

| Metric | Target (p50) | Target (p95) | Alarm Threshold |
|--------|--------------|--------------|-----------------|
| Cache Hit Latency | <500ms | <1s | >2s |
| Cache Miss Latency | <5s | <10s | >15s |
| OpenAI API Call | <3s | <8s | >30s (timeout) |
| DB Query (fetch entries) | <200ms | <500ms | >1s |
| DB Query (cache read) | <100ms | <300ms | >500ms |
| DB Query (cache write) | <200ms | <500ms | >1s |
| Total Request Size | <50KB | <100KB | >200KB |
| OpenAI Tokens Used | 800 | 1200 | >1500 |

### Cost Guardrails

**OpenAI Costs (gpt-4o) - With 2000 Token Budget**

- Input: $2.50 per 1M tokens
- Output: $10.00 per 1M tokens
- **Token Budget Per Request:**
  - Input: ~1400 tokens (150 system + 100 template + 1200 entries max)
  - Output: ~600 tokens (max 700 with buffer)
  - **Total: ~2000 tokens** (enforced)
- **Cost Per Request:** (1400 × $2.50 + 600 × $10.00) / 1M = **$0.0095** (~$0.01 per insight)

**Expected Usage**

- Active users: 1000
- Insights per user per month: 4 (weekly regenerations)
- Total requests: 4,000/month
- **Total cost: ~$40/month** (with 2000-token budget)
- Cache hit rate: 70% (reduces requests to 1,200/month actual API calls)
- **Actual cost with caching: ~$12/month**

**Cost Savings with Token Optimization**

- Without optimization: ~3000-4000 tokens per request → $0.015-$0.020
- With optimization (2000 tokens): $0.01
- **Savings: 50% reduction in token costs**

**Cost Limits**

- Per-user rate limit: 1 regeneration per hour (prevents abuse)
- Total budget cap: $100/month → alerts at $80
- Emergency kill switch: Disable feature if >$100/day
- Token budget enforcement: Hard cap at 2000 tokens total

**Monitoring**

- Track tokens per request (p50/p95/p99)
- Alert if p50 > 1500 tokens (approaching budget)
- **Alert if p95 > 2000 tokens (over budget)**
- Track daily spend: `(prompt_tokens × $2.50 + completion_tokens × $10.00) / 1M`
- Dashboard: Total insights generated, cache hit rate, avg cost, token usage distribution
- **New metric: `insights.token_budget_exceeded.total`** (counter)

---

## 6. MONITORING & ROLLOUT

### Metrics

**Usage Metrics**

- `insights.generated.total` (counter)
- `insights.cache_hit.total` (counter)
- `insights.cache_miss.total` (counter)
- `insights.error.total` (counter, labeled by error type)
- `insights.force_regenerate.total` (counter)

**Quality Metrics**

- `insights.validation_error.total` (counter, labeled by field)
- `insights.themes_count.histogram` (4-5 expected)
- `insights.summary_length.histogram` (≤140 chars)
- `insights.description_length.histogram` (150-180 words)

**Performance Metrics**

- `insights.latency.histogram` (labeled by cache_hit)
- `insights.openai_latency.histogram`
- `insights.db_query_latency.histogram`
- `insights.tokens_used.histogram` (prompt + completion)

**Cost Metrics**

- `insights.openai_cost.total` (counter, calculated)
- `insights.tokens_prompt.total` (counter)
- `insights.tokens_completion.total` (counter)

### Alerts

**Critical (Page On-Call)**

- Error rate >25% for 5 minutes
- OpenAI timeout rate >50% for 3 minutes
- Daily cost >$100 (emergency kill switch)
- Database unavailable (all queries fail)

**Warning (Slack Notification)**

- Error rate >10% for 10 minutes
- Cache miss rate >80% (cache not working?)
- p95 latency >15s for 5 minutes
- Daily cost >$80 (approaching budget)
- Validation error rate >5%

**Info (Dashboard Only)**

- Cache hit rate <50% (expected: 70-90%)
- p95 tokens used >1200 (prompt optimization needed)
- Themes count ≠4-5 (OpenAI not following schema)

### Staged Rollout Playbook

**Phase 1: Internal Testing (Day 1-2)**

- Deploy to dev environment
- Test with 5 internal accounts (various entry counts)
- Verify all scenarios (happy path, errors, cache)
- Check logs for errors/warnings
- Measure latency and costs

**Phase 2: Beta Users (Day 3-7)**

- Deploy to production
- Enable for 10% of users (feature flag)
- Monitor error rate, latency, costs
- Collect qualitative feedback (survey)
- Fix critical bugs if found

**Phase 3: General Availability (Day 8+)**

- Gradually increase to 25% → 50% → 100%
- Monitor metrics at each stage
- If error rate >10%, roll back to previous %
- Final rollout after 1 week stable operation

**Rollback Triggers**

| Trigger | Action |
|---------|--------|
| Error rate >25% for 5 min | Immediate rollback to 0% |
| Daily cost >$100 | Disable feature (kill switch) |
| OpenAI API unavailable >1 hour | Show cached insights only (disable regeneration) |
| Database migration failure | Rollback migration, fix, retry |
| Validation error rate >20% | Disable OpenAI call, return cached only |

**Rollback Procedure**

1. Set feature flag to 0% (disables new insights generation)
2. Verify users can still see cached insights
3. Investigate root cause (logs, Sentry, metrics)
4. Deploy fix to dev/staging
5. Re-test all scenarios
6. Re-enable for 10% → 25% → 100%

---

## 7. ACCEPTANCE CRITERIA

### Technical

- [ ] Edge Function deploys successfully without errors
- [ ] OpenAI API integration returns valid JSON
- [ ] Response validation catches all malformed responses
- [ ] Cache hit returns insights in <500ms (p50)
- [ ] Cache miss returns insights in <5s (p50)
- [ ] Database migration runs without errors
- [ ] RLS policies enforce user ownership
- [ ] Auto-invalidation trigger works on new entry
- [ ] Error responses include user-friendly messages
- [ ] All 10 error scenarios handled correctly
- [ ] Swift models decode API responses correctly
- [ ] InsightsService handles all error types
- [ ] InsightViewModel state machine works correctly
- [ ] Pull-to-refresh forces regeneration
- [ ] Unit tests pass (5 test suites)
- [ ] Manual test checklist complete (9 scenarios)

### UX

- [ ] Loading state shows spinner + message
- [ ] Empty state (<3 entries) shows clear CTA
- [ ] Error state shows retry button
- [ ] Insights display in <1s for cached results
- [ ] Themes render with emojis correctly
- [ ] Summary is readable (≤140 chars)
- [ ] Description references ≥2 entry titles
- [ ] Source entries show formatted dates
- [ ] "Updated X ago" shows for cached insights
- [ ] Pull-to-refresh animation smooth
- [ ] No UI freezes during generation
- [ ] Error messages are user-friendly (no technical jargon)
- [ ] Transitions between states are smooth
- [ ] Typography/colors match design system

### Business

- [ ] Average cost per insight ≤$0.01
- [ ] Cache hit rate ≥70% (reduces costs)
- [ ] Error rate <5% in production
- [ ] p95 latency <10s (acceptable UX)
- [ ] 95%+ of insights pass validation (themes 4-5, summary ≤140 chars)
- [ ] No PII leaks in logs or errors
- [ ] OpenAI prompts don't generate harmful content
- [ ] Feature enables 100% of users without issues
- [ ] No regression in existing features (Journal, etc.)
- [ ] Rollback plan tested and documented

---

## APPENDIX

### Key Files Summary

#### Backend - Edge Functions

| File | Lines (Est) | Priority |
|------|-------------|----------|
| **fetch-journal-entries/** |
| `functions/fetch-journal-entries/index.ts` | 130 | P0 |
| `functions/fetch-journal-entries/types.ts` | 60 | P0 |
| `functions/fetch-journal-entries/transformer.ts` | 150 | P0 |
| `functions/fetch-journal-entries/dateUtils.ts` | 30 | P0 |
| **generate-insights/** |
| `functions/generate-insights/index.ts` | 200 | P0 |
| `functions/generate-insights/types.ts` | 100 | P0 |
| `functions/generate-insights/prompts.ts` | 80 | P0 |
| `functions/generate-insights/tokenOptimizer.ts` | 120 | P0 |
| `functions/generate-insights/validation.ts` | 120 | P0 |
| **Subtotal Backend:** | **~990 lines** |

#### Frontend - Swift/SwiftUI

| File | Lines (Est) | Priority |
|------|-------------|----------|
| `Models/Insight.swift` | 100 | P0 |
| `Models/Theme.swift` | 50 | P0 |
| `Models/SourceEntry.swift` | 40 | P0 |
| `Services/InsightsService.swift` | 120 | P0 |
| `ViewModels/InsightViewModel.swift` | 80 | P0 |
| `Views/Insights/InsightsView.swift` | 150 | P0 |
| **Subtotal Frontend:** | **~540 lines** |

#### Database

| File | Lines (Est) | Priority |
|------|-------------|----------|
| `migrations/20251023100000_update_insights_schema.sql` | 50 | P0 |
| **Subtotal Database:** | **~50 lines** |

**Total estimated lines: ~1,580** (across 15 files)

### Dependencies

**Backend (Deno)**

- `npm:openai@4` - OpenAI SDK
- `@supabase/supabase-js` - Supabase client (included)

**Frontend (Swift)**

- `Supabase` - Already integrated
- No additional dependencies needed

### Environment Variables

**Supabase Secrets** (set via CLI)

```bash
# Required
supabase secrets set OPENAI_API_KEY=sk-proj-...

# Optional (already set)
SUPABASE_URL=https://fhsgvlbedqwxwpubtlls.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...
```

### Useful Commands

```bash
# Backend
cd supabase
supabase functions serve generate-insights --no-verify-jwt  # Local dev
supabase functions deploy generate-insights                  # Deploy
supabase functions logs generate-insights --tail             # Stream logs
supabase secrets set OPENAI_API_KEY=sk-...                   # Set secret

# Database
supabase migration new update_insights_schema                # Create migration
supabase db push                                             # Apply migrations
supabase db reset                                            # Reset local DB

# Testing
curl -i --location --request POST \
  'http://localhost:54321/functions/v1/generate-insights' \
  --header 'Authorization: Bearer YOUR_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"forceRegenerate": false, "daysBack": 30}'
```

---

**END OF PLAN**

*This document is ready for implementation. All sections are complete with specific file paths, function signatures, error handling, and acceptance criteria.*
