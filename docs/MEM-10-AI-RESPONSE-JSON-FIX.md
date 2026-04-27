# MEM-10: AI Response JSON and Cut-off Fix

## Issue Summary

AI responses were sometimes:
1. **Containing raw JSON** (e.g. `{body: ....`) displayed to users instead of natural text
2. **Getting cut off early** due to token limits

## Root Causes

1. **Model output format**: The AI model was instructed to output JSON. When parsing failed or the model wrapped output in extra text, raw JSON could leak to the UI.
2. **Token limits**: `max_tokens: 1500` in generate-insights and the missing chat-with-entries function meant responses could truncate mid-output.
3. **No chat edge function**: The `chat-with-entries` edge function was referenced in `InsightsService` but did not exist.

## Fixes Applied

### 1. Created `chat-with-entries` Edge Function

**Location**: `supabase/functions/chat-with-entries/`

- **Robust JSON parsing**: `parseAndSanitizeResponse()` never returns raw model output. It:
  - Parses JSON directly when valid
  - Extracts JSON from markdown code blocks or wrapped text via `extractJsonFromText()`
  - Throws if parsing fails (no raw JSON ever reaches the client)

- **Higher max_tokens**: `MAX_TOKENS = 2500` to prevent cut-off

- **Strict system prompt**: Instructs the model to return ONLY valid JSON, no commentary

### 2. Increased `generate-insights` max_tokens

- Changed from `1500` to `2200` to reduce truncation of insight descriptions and themes

### 3. Swift Client Defensive Parsing

**AIOutputContent** (`MeetMemento/Components/AIChat/AIOutputComponent.swift`):
- Added `sanitizeBody()` to strip leaked JSON from the `body` field
- Custom `init(from decoder:)` applies sanitization during decode
- If `body` looks like `{"body": "actual content"}`, extracts the inner content

**JournalCitation** (`MeetMemento/Components/AIChat/ChatMessage.swift`):
- Custom `init(from decoder:)` for lenient decoding
- Handles missing `id`, invalid `entry_id` UUIDs, and date format variations

### 4. Wired AIChatView to Real Backend

- Replaced mock AI response with `InsightsService.shared.chat()`
- Uses `entryViewModel.entries` as context
- Error handling shows a fallback message on failure

## Deployment

1. **Deploy the new edge function**:
   ```bash
   supabase functions deploy chat-with-entries
   ```

2. **Redeploy generate-insights** (for max_tokens change):
   ```bash
   supabase functions deploy generate-insights
   ```

3. Ensure `OPENAI_API_KEY` is set in Supabase Edge Function secrets.

## Verification

- Chat responses should never show raw JSON like `{body: ...`
- Responses should complete without mid-sentence truncation
- Insights (generate-insights) should have fuller descriptions
