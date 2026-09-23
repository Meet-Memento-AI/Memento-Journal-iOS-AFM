# System Prompt Implementation Plan (MEM-22)

## Executive Summary

Implement the base Memento journaling companion system prompt and personalize it using input from `LearnAboutYourselfView` (freeform self-reflection text) and `YourGoalsView` (selected journaling goals). The system prompt will drive the conversational AI in `AIChatView`, which helps users explore journal entries.

---

## Current Implementation Analysis

### 1. Onboarding Views & Data Flow

| View | Input | Storage | Backend Column |
|------|-------|---------|----------------|
| **LearnAboutYourselfView** | Freeform text (100–2000 chars): "What would you like to learn about yourself?" | `OnboardingViewModel.personalizationText` | `user_profiles.onboarding_self_reflection` |
| **YourGoalsView** | Multi-select chips: Self awareness, Emotion mapping, Calming control, Stress relief, Thoughtful responses, Self-kindness, Honesty, Compassion | `OnboardingViewModel.selectedGoals` | **Not persisted** (see Gap #2) |

**Flow:**
- `OnboardingFlowView` / `OnboardingCoordinatorView` → `handleLearnAboutYourselfComplete` → `onboardingViewModel.personalizationText`
- `handleYourGoalsComplete` → `onboardingViewModel.selectedGoals`
- `finishSecuritySetup` → `createFirstJournalEntry(personalizationText)` → `completeOnboarding()`

### 2. AI Chat Infrastructure

| Component | Status | Notes |
|-----------|--------|-------|
| **AIChatView** | Exists (mock) | Uses mock responses; no real API call |
| **InsightsService.chat()** | Exists | Invokes `chat-with-entries` Supabase Edge Function |
| **chat-with-entries Edge Function** | **Missing** | Only `generate-insights` and `new-user-insights` exist |
| **UserContext / user_profiles** | Exists | `onboarding_self_reflection` persisted; `identified_themes` exists (different from YourGoalsView goals) |

### 3. Existing System Prompts

- **generate-insights** (`supabase/functions/generate-insights/index.ts`): Uses its own system prompt for structured JSON output (themes, sentiment, annotations). **Different use case** from the conversational Memento companion.
- **new-user-insights**: Handles first-journal-entry analysis and theme identification.

### 4. Schema Notes

- `user_profiles.identified_themes`: AI-identified themes (3–6) from `themes` table (e.g. `stress-energy`, `anxiety-worry`).
- YourGoalsView goals ("Self awareness", "Emotion mapping", etc.) **do not map 1:1** to `themes.name`. A `selected_goals` (or similar) column is needed for user-selected goals.

---

## Gaps Identified

1. **chat-with-entries Edge Function** does not exist; must be created.
2. **selectedGoals from YourGoalsView** are not persisted. Need migration for `selected_goals` (or reuse `identified_themes` with a mapping).
3. **OnboardingViewModel** has TODO stubs: `createFirstJournalEntry`, `completeOnboarding`, `saveProfileData` do not persist to Supabase.
4. **UserContext** is not loaded by AIChatView / chat service; personalization data must be fetched and passed to the system prompt.

---

## Implementation Plan

### Phase 1: Data Layer – Persist Onboarding Data

#### 1.1 Database Migration: Add `selected_goals` to user_profiles

**File:** `supabase/migrations/YYYYMMDD_add_selected_goals.sql`

```sql
-- Add selected_goals for YourGoalsView chip selections
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS selected_goals TEXT[];
```

- Store array of goal strings: `["Self awareness", "Emotion mapping", ...]`
- No FK to `themes` (different domain from `identified_themes`)

#### 1.2 OnboardingViewModel – Save to Supabase

- Implement `createFirstJournalEntry` to create the first entry.
- Implement `completeOnboarding` to:
  - Update `user_profiles`: `onboarding_self_reflection`, `selected_goals`
  - Mark onboarding complete (e.g. `has_completed_onboarding` flag if exists)
- Implement `saveProfileData` / `loadCurrentState` to read/write `user_profiles`.

#### 1.3 UserContext Model Update

- Add `selectedGoals: [String]?` and map to `selected_goals`.
- Ensure UserContext is fetched when loading chat context.

---

### Phase 2: Create `chat-with-entries` Edge Function

#### 2.1 Function Structure

**Path:** `supabase/functions/chat-with-entries/index.ts`

**Request body:** (matches `InsightsService.ChatRequest`)

```ts
{
  messages: [{ content: string, isFromUser: string }],
  entries: [{ date, title, content, word_count }],
  systemPromptContext?: {  // NEW: personalization
    onboardingSelfReflection?: string,
    selectedGoals?: string[]
  }
}
```

**Response:** Stream or JSON with `AIOutputContent`-compatible structure (heading1, heading2, body, citations).

#### 2.2 OpenAI Integration

- Use OpenAI chat completions API (similar to `generate-insights`).
- System message = base Memento prompt + personalization sections.
- User messages = conversation history + retrieved journal entries as context.

---

### Phase 3: Base System Prompt

#### 3.1 Core Memento Prompt (from Issue)

Use the provided prompt as the base:

```
You are Memento, a journaling companion. You help users explore their journal entries to discover patterns and understand themselves.

ROLE: You are a mirror, not a therapist. Users are experts on their own lives. You reflect what you see in their entries and ask questions that help them find their own insights.

VOICE: Write like a thoughtful friend. Warm, honest, curious. Never clinical, robotic, or prescriptive.

RESPONSE FORMAT:
1. Acknowledge: what you found in their entries (1-2 sentences)
2. Insight: patterns, connections, or themes with specific dates (2-4 sentences)
3. Reflect: one question that invites deeper thinking (1-2 sentences)

Keep responses 3-10 sentences total. Use line breaks between sections. Never write walls of text.

GROUNDING RULES:
- Always cite specific entry dates when referencing journal content
- For 1-3 entries: name each date. For 4-10: group by timeframe. For 10+: summarize frequency.
- Never fabricate entries, quotes, dates, or patterns not in the provided context
- If insufficient data exists, say so: "I don't see entries about that yet."

DO:
- Notice recurring themes, emotional shifts, contradictions, and timeline connections
- Reference entries naturally: "In your March 5th entry, you mentioned..."
- Use phrases: "I notice...", "It seems like...", "I'm curious about...", "Looking at your entries..."
- Present contradictions gently: "You've said two different things about this — both can be true."
- Ask open questions instead of giving answers

DO NOT:
- Diagnose conditions or give medical/legal/financial advice
- Say "you should" or tell users what to do
- Predict outcomes or claim certainty about other people's motivations
- Use "obviously", "clearly", "you always", "you never", "the problem is"
- Claim emotions, say "I miss you" or "I'm proud of you"
- Fabricate any journal content

CONCERNING PATTERNS: If entries show repeated hopelessness, self-harm references, or crisis indicators — acknowledge gently, express concern without alarm, suggest professional support, provide 988 Suicide & Crisis Lifeline. Do not attempt to treat.

Every response should leave the user feeling heard, curious about themselves, and glad they journaled.
```

---

### Phase 4: Personalization Sections

#### 4.1 LearnAboutYourselfView → Personalization

Append when `onboardingSelfReflection` is present:

```
PERSONALIZATION (from user's onboarding):
The user shared during onboarding: "[onboarding_self_reflection]"
Use this to guide your attention when exploring their entries. Pay special notice to themes, goals, or questions they expressed wanting to explore. Reference this naturally when relevant, e.g. "You mentioned wanting to understand X — I see a thread of that in your entries."
```

#### 4.2 YourGoalsView → Personalization

Append when `selectedGoals` is present:

```
JOURNALING GOALS (user-selected themes to explore):
The user chose to focus on: [comma-separated goals]
When relevant, connect insights to these goals. Don't force every response to touch on all of them; use them as a lens for what might matter most to the user.
```

**Example combined personalization:**

```
PERSONALIZATION (from user's onboarding):
The user shared during onboarding: "I want to understand why I react so strongly to criticism at work and learn to respond more calmly."

JOURNALING GOALS (user-selected themes to explore):
The user chose to focus on: Self awareness, Emotion mapping, Thoughtful responses

Use this to guide your attention when exploring their entries...
```

---

### Phase 5: Wire AIChatView to Real Backend

#### 5.1 Fetch UserContext Before Chat

- On AIChatView load (or first message): fetch `user_profiles` for current user.
- Extract `onboarding_self_reflection`, `selected_goals`.

#### 5.2 Update InsightsService.chat()

- Extend request body to include `systemPromptContext`.
- Pass `UserContext.onboardingSelfReflection` and `UserContext.selectedGoals` (or equivalent).

#### 5.3 Replace Mock in AIChatView

- Call `InsightsService.chat(messages:entries:)` instead of mock delay.
- Handle loading, errors, and parsing `AIOutputContent` into `ChatMessage`.

---

## File Change Summary

| File | Action |
|------|--------|
| `supabase/migrations/YYYYMMDD_add_selected_goals.sql` | **Create** – add `selected_goals` column |
| `supabase/functions/chat-with-entries/index.ts` | **Create** – Memento chat edge function |
| `supabase/functions/chat-with-entries/types.ts` | **Create** – request/response types |
| `withMemento/ViewModels/OnboardingViewModel.swift` | **Update** – implement persistence to user_profiles |
| `withMemento/Models/UserContext.swift` | **Update** – add `selectedGoals` |
| `withMemento/Services/InsightsService.swift` | **Update** – pass systemPromptContext to chat |
| `withMemento/Views/AI-Chat/AIChatView.swift` | **Update** – fetch UserContext, call real API, remove mock |
| (Optional) `withMemento/Services/UserContextService.swift` | **Create** – fetch UserContext from user_profiles |

---

## Risk & Dependencies

1. **chat-with-entries** is referenced by `InsightsService` but missing; creating it unblocks real chat.
2. **Onboarding persistence**: If `createFirstJournalEntry` / `completeOnboarding` remain stubs, personalization will be empty for new users until those are implemented.
3. **Backward compatibility**: Users without `selected_goals` or `onboarding_self_reflection` should still get the base prompt (no personalization sections).

---

## Testing Checklist

- [ ] New user completes LearnAboutYourselfView → `onboarding_self_reflection` saved
- [ ] New user completes YourGoalsView → `selected_goals` saved
- [ ] AIChatView fetches UserContext before/with first message
- [ ] chat-with-entries receives `systemPromptContext` and builds personalized system message
- [ ] AI responses cite journal entries with dates
- [ ] AI responses reflect user's stated goals when relevant
- [ ] Users without onboarding data receive base prompt only
- [ ] Concerning content triggers appropriate safety guidance (988, professional support)

---

## Recommended Implementation Order

1. **Phase 1.1** – Migration for `selected_goals`
2. **Phase 3 + 4** – Define base prompt + personalization logic (can be done in code first)
3. **Phase 2** – Create `chat-with-entries` edge function with full prompt construction
4. **Phase 1.2–1.3** – Persist onboarding data, update UserContext
5. **Phase 5** – Wire AIChatView to real backend and UserContext

---

## Gemini Context Caching (Added)

The chat-with-entries function uses **Google Gemini** with explicit context caching per [Gemini best practices](https://ai.google.dev/gemini-api/docs/caching):

- **Cached**: system instruction (base prompt + personalization) + journal entries
- **Per-request**: conversation messages only
- **Cache metadata**: stored in `user_chat_caches` (user_id, entries_hash, cache_name, expires_at)
- **TTL**: 1 hour
- **Environment**: `GEMINI_API_KEY` required

See `docs/GEMINI_CONTEXT_CACHING_PLAN.md` for full architecture.

## System Prompt as .md File (Added)

The base prompt and personalization template are stored in `supabase/functions/chat-with-entries/system_prompt.md`:

- **Base prompt**: Content before `<!-- PERSONALIZATION_TEMPLATE -->`
- **Placeholders**: `{{onboarding_reflection}}`, `{{selected_goals}}`
- **Conditional blocks**: `ONBOARDING_REFLECTION_BLOCK` and `SELECTED_GOALS_BLOCK` are included only when the user has that data

See `docs/SYSTEM_PROMPT_FILE_PLAN.md` for the editing workflow.

---

## Appendix: YourGoalsView Goals vs themes Table

YourGoalsView uses different labels than the `themes` table:

| YourGoalsView | themes.name (example) |
|--------------|------------------------|
| Self awareness | confidence-mindset, meaning-values |
| Emotion mapping | anxiety-worry, self-compassion |
| Calming control | anxiety-worry, sleep-rest |
| Stress relief | stress-energy, habits-routine |
| Thoughtful responses | habits-routine, meaning-values |
| Self-kindness | self-compassion |
| Honesty | meaning-values |
| Compassion | self-compassion, relationships-connection |

Storing `selected_goals` as the user-facing strings ("Self awareness", etc.) keeps the prompt readable and avoids schema coupling. The AI can interpret these goals without needing a mapping to `themes`.
