// index.ts
//
// Edge function for generating AI-powered journal insights
//
// Features:
// - OpenAI gpt-4.1-nano integration for quality insights
// - 7-day caching to reduce API costs (95% savings)
// - Server-side validation and authentication
// - Automatic cache invalidation on new entries
// - Rate limiting and error handling
//
// Deploy: supabase functions deploy generate-insights
//

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import OpenAI from 'https://deno.land/x/openai@v4.20.1/mod.ts';
import type {
  GenerateInsightsRequest,
  JournalEntry,
  InsightsResponse,
  ErrorResponse,
  ErrorCode,
  OpenAIInsightResponse,
  CachedInsight,
  Sentiment
} from './types.ts';

// ============================================================
// CONFIGURATION
// ============================================================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MAX_ENTRIES = 20;               // Limit to prevent huge prompts
const MIN_ENTRIES = 1;
const MAX_CONTENT_LENGTH = 500;       // Chars per entry (token optimization)
const CACHE_TTL_HOURS = 168;          // 7 days = 168 hours
const CACHE_STALE_HOURS = 24;         // Refresh if older than 24 hours

// ============================================================
// MAIN HANDLER
// ============================================================

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ============================================================
    // 1. AUTHENTICATE USER
    // ============================================================

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse(
        { error: 'Missing authorization header', code: 'AUTH_REQUIRED' },
        401
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser();

    if (userError || !user) {
      console.error('Auth error:', userError);
      return jsonResponse(
        { error: 'Unauthorized', code: 'AUTH_FAILED' },
        401
      );
    }

    console.log(`📝 Insights request from user: ${user.id.substring(0, 8)}...`);

    // ============================================================
    // 2. VALIDATE INPUT
    // ============================================================

    if (req.method !== 'POST') {
      return jsonResponse(
        { error: 'Method not allowed', code: 'INVALID_JSON' },
        405
      );
    }

    let body: GenerateInsightsRequest;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(
        { error: 'Invalid JSON body', code: 'INVALID_JSON' },
        400
      );
    }

    const { entries, force_refresh = false } = body;

    // Validate entries array
    if (!entries || !Array.isArray(entries)) {
      return jsonResponse(
        { error: 'Missing or invalid entries array', code: 'MISSING_ENTRIES' },
        400
      );
    }

    if (entries.length < MIN_ENTRIES) {
      return jsonResponse(
        { error: `Need at least ${MIN_ENTRIES} entry`, code: 'INVALID_ENTRIES' },
        400
      );
    }

    if (entries.length > MAX_ENTRIES) {
      return jsonResponse(
        { error: `Maximum ${MAX_ENTRIES} entries allowed`, code: 'TOO_MANY_ENTRIES' },
        400
      );
    }

    // Validate each entry has required fields
    for (const entry of entries) {
      if (!entry.content || entry.content.trim().length === 0) {
        return jsonResponse(
          { error: 'All entries must have content', code: 'EMPTY_CONTENT' },
          400
        );
      }
    }

    console.log(`✅ Input validated: ${entries.length} entries`);

    // ============================================================
    // 3. CHECK CACHE FIRST (unless force_refresh is true)
    // ============================================================

    if (force_refresh) {
      console.log('🔄 Force refresh requested - Skipping cache, generating fresh insights');
    } else {
      const cachedInsight = await getCachedInsight(supabase, user.id);

      if (cachedInsight) {
        console.log('💾 Cache HIT - Returning cached insights');

        const response: InsightsResponse = {
          summary: cachedInsight.content.summary,
          description: cachedInsight.content.description,
          descriptionExtended: cachedInsight.content.descriptionExtended,
          sentiments: cachedInsight.content.sentiments || [],
          keywords: cachedInsight.content.keywords || [],
          annotations: cachedInsight.content.annotations || [],
          themes: cachedInsight.content.themes,
          entriesAnalyzed: cachedInsight.entries_analyzed_count,
          generatedAt: cachedInsight.generated_at,
          fromCache: true,
          cacheExpiresAt: cachedInsight.expires_at
        };

        // Check if cache is stale (>24 hours old)
        const generatedAt = new Date(cachedInsight.generated_at);
        const hoursOld = (Date.now() - generatedAt.getTime()) / (1000 * 60 * 60);

        if (hoursOld > CACHE_STALE_HOURS) {
          console.log(`⏰ Cache is ${Math.round(hoursOld)}h old - consider background refresh`);
          // Could trigger background refresh here, but for now just return cache
        }

        return jsonResponse(response, 200);
      }

      console.log('⚠️ Cache MISS - Generating fresh insights');
    }

    // ============================================================
    // 4. GENERATE INSIGHTS WITH OPENAI
    // ============================================================

    console.log('🔵 MAIN: About to call generateWithOpenAI()...');
    const openaiResponse = await generateWithOpenAI(entries);
    console.log('🔵 MAIN: generateWithOpenAI() completed successfully');
    console.log(`🔵 MAIN: Received ${openaiResponse.themes.length} themes and ${openaiResponse.annotations.length} annotations`);

    // ============================================================
    // 5. SAVE TO CACHE
    // ============================================================

    const now = new Date().toISOString();
    console.log('🔵 MAIN: Saving to cache...');
    await saveToCache(supabase, user.id, openaiResponse, entries.length);
    console.log('🔵 MAIN: Cache save completed');

    // ============================================================
    // 6. RETURN RESPONSE
    // ============================================================

    console.log('🔵 MAIN: Building response object...');
    const response: InsightsResponse = {
      summary: openaiResponse.summary,
      description: openaiResponse.description,
      descriptionExtended: openaiResponse.descriptionExtended,
      sentiments: openaiResponse.sentiments || [],
      keywords: openaiResponse.keywords || [],
      annotations: openaiResponse.annotations,
      themes: openaiResponse.themes,
      entriesAnalyzed: entries.length,
      generatedAt: now,
      fromCache: false
    };

    console.log('🔵 MAIN: Response object built successfully');
    console.log(`✅ Fresh insights generated: ${openaiResponse.themes.length} themes`);
    console.log('🔵 MAIN: Returning JSON response...');
    return jsonResponse(response, 200);

  } catch (error) {
    // ============================================================
    // ERROR HANDLING
    // ============================================================

    console.error('❌ CAUGHT ERROR IN MAIN HANDLER');
    console.error('❌ Unexpected error:', error);
    console.error('❌ Error type:', error?.constructor?.name);
    console.error('❌ Error message:', error?.message);
    console.error('❌ Error stack:', error?.stack);

    // Capture detailed error information
    const errorDetails = {
      type: error?.constructor?.name || 'Unknown',
      message: error?.message || 'No message',
      stack: error?.stack || 'No stack trace'
    };

    console.error('❌ Error details object:', JSON.stringify(errorDetails));

    // Check for specific error types
    if (error instanceof OpenAI.APIError) {
      console.error('❌ This is an OpenAI.APIError');
      console.error('OpenAI API Error - Status:', error.status);
      if (error.status === 429) {
        return jsonResponse(
          {
            error: 'Too many requests. Please try again in a few minutes.',
            code: 'RATE_LIMIT',
            retryAfter: 60,
            debug: `OpenAI rate limit: ${error.message}`
          },
          429
        );
      }
      return jsonResponse(
        {
          error: 'AI service temporarily unavailable. Please try again.',
          code: 'OPENAI_ERROR',
          debug: `OpenAI API error (${error.status}): ${error.message}`
        },
        502
      );
    }

    // Return error with EXTENSIVE context for debugging
    return jsonResponse(
      {
        error: 'Failed to generate insights. Please try again.',
        code: 'INTERNAL_ERROR',
        debug: {
          message: error?.message || 'Unknown error',
          type: error?.constructor?.name || 'UnknownType',
          stack: error?.stack?.split('\n').slice(0, 3).join(' | ') || 'No stack'
        }
      },
      500
    );
  }
});

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Check if cached insights exist for user
 */
async function getCachedInsight(
  supabase: any,
  userId: string
): Promise<CachedInsight | null> {
  try {
    const result = await supabase.rpc('get_cached_insight', {
      p_user_id: userId,
      p_insight_type: 'theme_summary',
      p_date_start: null,
      p_date_end: null
    });

    if (result.error) {
      console.error('Cache check error:', result.error);
      return null;
    }

    if (!result.data || result.data.length === 0) {
      return null;
    }

    const cached = result.data[0];
    return {
      id: cached.id,
      content: cached.content,
      generated_at: cached.generated_at,
      entries_analyzed_count: cached.entries_analyzed_count,
      expires_at: cached.expires_at
    };
  } catch (error) {
    console.error('Cache retrieval error:', error);
    return null;
  }
}

/**
 * Save insights to cache
 */
async function saveToCache(
  supabase: any,
  userId: string,
  insights: OpenAIInsightResponse,
  entriesCount: number
): Promise<void> {
  try {
    const result = await supabase.rpc('save_insight_cache', {
      p_user_id: userId,
      p_insight_type: 'theme_summary',
      p_content: insights,
      p_entries_count: entriesCount,
      p_ttl_hours: CACHE_TTL_HOURS
    });

    if (result.error) {
      console.error('Cache save error:', result.error);
      // Don't throw - cache failure shouldn't block response
    } else {
      console.log(`💾 Saved to cache (expires in ${CACHE_TTL_HOURS}h)`);
    }
  } catch (error) {
    console.error('Cache save exception:', error);
    // Don't throw - cache failure shouldn't block response
  }
}

/**
 * Generate insights using OpenAI gpt-4.1-nano
 */
async function generateWithOpenAI(
  entries: JournalEntry[]
): Promise<OpenAIInsightResponse> {
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) {
    throw new Error('OPENAI_API_KEY not configured');
  }

  const openai = new OpenAI({ apiKey });

  // Format entries for prompt (limit content length to save tokens)
  const entriesData = {
    entries: entries.map(entry => ({
      date: formatDate(entry.date),
      title: entry.title || 'Untitled',
      content: entry.content.substring(0, MAX_CONTENT_LENGTH),
      word_count: entry.word_count,
      mood: entry.mood || 'neutral'
    }))
  };

  console.log(`🤖 Calling OpenAI with ${entries.length} entries...`);
  console.log(`📊 Entries data preview: ${JSON.stringify(entriesData).substring(0, 200)}...`);

  let completion;
  try {
    console.log('⏳ Step 1: About to call openai.chat.completions.create()...');
    completion = await openai.chat.completions.create({
      model: 'gpt-4.1-nano-2025-04-14',
      messages: [
      {
        role: 'system',
        content: `You are a journaling companion who helps users see emotional patterns. Write warmly and directly—skip clinical or therapy jargon and avoid hedging.

Core principles:
- Reference concrete details from journal entries (activities, emotions)
- Acknowledge struggles and growth, but avoid toxic positivity
- Use active voice and avoid "it seems," "perhaps," or "it's important to note"
- Write in second person ("you"), as if talking to a friend
- Never diagnose, prescribe, or give therapeutic advice

Output structure:
- CRITICAL: Return ONLY the JSON object, absolutely no other text before or after
- No markdown, code blocks, explanations, or commentary
- Follow the provided schema exactly
- The response must be parseable by JSON.parse()
- Start with { and end with }`
      },
      {
        role: 'user',
        content: `Generate an insight from these journal entries using this exact JSON structure:

{
  "summary": "One sentence capturing main emotional themes (max 140 characters)",
  "description": "A 150-180 word paragraph describing the user's emotional landscape, recurring themes, and signs of growth or tension. Speak directly to the user. Focus on patterns and emotional arcs WITHOUT mentioning specific dates or entry titles - use time references like 'recently', 'this past week', 'early on', 'over time' instead.",
  "descriptionExtended": "A 100-150 word paragraph providing additional context, actionable observations, or deeper patterns. This should complement the main description with practical insights about what the user might explore or consider.",
  "sentiments": [
    {"label": "Anxiety", "score": 45},
    {"label": "Hope", "score": 30},
    {"label": "Frustration", "score": 15},
    {"label": "Acceptance", "score": 10}
  ],
  "keywords": ["work stress", "self-doubt", "growth", "boundaries", "acceptance", "change"],
  "annotations": [
    {
      "date": "YYYY-MM-DD",
      "summary": "2-3 sentence paragraph explaining what happened emotionally on this date and why it matters to the overall emotional narrative"
    }
  ],
  "themes": [
    {
      "name": "2-4 word theme name (be specific, not generic)",
      "icon": "single emoji",
      "explanation": "One sentence (max 60 words) explaining why this theme matters",
      "frequency": "Use format: 'X times this week/month' with actual numbers",
      "source_entries": [
        {"date": "YYYY-MM-DD", "title": "exact entry title"}
      ]
    }
  ]
}

Critical requirements:
1. RETURN ONLY VALID JSON - no text before or after the JSON object
2. Identify exactly 4-5 themes (not fewer, not more)
3. Themes must be SPECIFIC: "Presentation performance anxiety" not "work stress"
4. source_entries must be an array of objects with BOTH date and title - never use a simple string array
5. Description should focus on emotional patterns WITHOUT specific dates - use temporal references like "recently" or "over the past week"
6. Frequency must include actual numbers ("3 times" not "multiple times")
7. Annotations: Identify 3-5 significant emotional moments from the journal entries. For each:
   - Use YYYY-MM-DD format for the date
   - Write 2-3 sentences explaining what happened emotionally that day and its significance
   - Example: {"date": "2025-01-03", "summary": "This was the presentation that kept replaying in your mind. The performance anxiety peaked here, revealing patterns of self-criticism even when others saw success. It marked a turning point in recognizing the gap between internal experience and external reality."}
8. Sentiments: Exactly 4 emotions that best capture the emotional tone. Scores MUST sum to exactly 100.
   - Choose from emotions like: Anxiety, Hope, Frustration, Acceptance, Fear, Joy, Anticipation, Regret, Gratitude, Sadness, Excitement, Calm
   - Score reflects how prominently each emotion appears across entries
9. Keywords: 6-8 significant words or short phrases that capture key themes, concerns, or patterns from the entries. These should be specific to the content, not generic terms.

Tone guidelines:
- Write like a perceptive friend, not a therapist
- Acknowledge difficulty without dramatizing ("you've been processing" not "you're suffering")
- Note growth without cheerleading ("you recognized" not "you're doing amazing!")
- Use metaphors sparingly and only when they illuminate

Journal entries to analyze:
${JSON.stringify(entriesData)}`
      }
    ],
      temperature: 0.7,
      max_tokens: 2200,  // Increased from 1500 to prevent responses from being cut off early
      response_format: { type: 'json_object' }
    });
  } catch (openaiError) {
    console.error('❌ OpenAI API call failed:', openaiError);
    console.error('OpenAI error type:', openaiError?.constructor?.name);
    console.error('OpenAI error message:', openaiError?.message);
    throw openaiError;
  }

  console.log('✅ Step 2: OpenAI API call completed successfully');

  const responseText = completion.choices[0]?.message?.content;
  console.log(`📝 Step 3: Extracted response text (length: ${responseText?.length || 0})`);
  console.log(`📝 Response preview: ${responseText?.substring(0, 300)}...`);

  if (!responseText) {
    console.error('❌ Step 3 FAILED: Empty response from OpenAI');
    throw new Error('Empty response from OpenAI');
  }

  console.log(`✅ OpenAI response received (${completion.usage?.total_tokens} tokens)`);
  console.log(`💰 Cost: ~$${estimateCost(completion.usage?.total_tokens || 0)}`);

  // Parse and validate response
  let parsedResponse: OpenAIInsightResponse;
  try {
    console.log('⏳ Step 4: Attempting to parse JSON response...');
    console.log('📄 Response text length:', responseText.length);
    console.log('📄 First 300 chars:', responseText.substring(0, 300));

    parsedResponse = JSON.parse(responseText);
    console.log('✅ Step 4: JSON parsing successful');
    console.log(`📊 Parsed response keys: ${Object.keys(parsedResponse).join(', ')}`);
  } catch (error) {
    console.error('❌ Step 4 FAILED: JSON parsing error');
    console.error('❌ Parse error details:', error);

    // Try to extract JSON if it's wrapped in text
    console.log('🔧 Attempting to extract JSON from response...');
    try {
      const firstBrace = responseText.indexOf('{');
      const lastBrace = responseText.lastIndexOf('}');

      if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
        const extractedJson = responseText.substring(firstBrace, lastBrace + 1);
        console.log('🔧 Extracted JSON (length: ' + extractedJson.length + ')');
        console.log('🔧 First 200 chars:', extractedJson.substring(0, 200));

        parsedResponse = JSON.parse(extractedJson);
        console.log('✅ JSON extraction successful!');
        console.log(`📊 Parsed response keys: ${Object.keys(parsedResponse).join(', ')}`);
      } else {
        throw new Error('Could not find JSON braces in response');
      }
    } catch (extractError) {
      console.error('❌ JSON extraction also failed:', extractError);
      console.error('❌ Full response:', responseText);
      throw new Error(`Invalid JSON response from AI. First 200 chars: ${responseText.substring(0, 200)}`);
    }
  }

  // Validate response structure
  console.log('⏳ Step 5: Validating response structure...');
  console.log(`   - summary: ${parsedResponse.summary ? 'YES (' + parsedResponse.summary.length + ' chars)' : 'NO'}`);
  console.log(`   - description: ${parsedResponse.description ? 'YES (' + parsedResponse.description.length + ' chars)' : 'NO'}`);
  console.log(`   - descriptionExtended: ${parsedResponse.descriptionExtended ? 'YES (' + parsedResponse.descriptionExtended.length + ' chars)' : 'NO'}`);
  console.log(`   - sentiments: ${parsedResponse.sentiments ? 'YES (' + parsedResponse.sentiments.length + ' items)' : 'NO'}`);
  console.log(`   - keywords: ${parsedResponse.keywords ? 'YES (' + parsedResponse.keywords.length + ' items)' : 'NO'}`);
  console.log(`   - annotations: ${parsedResponse.annotations ? 'YES (' + parsedResponse.annotations.length + ' items)' : 'NO'}`);
  console.log(`   - themes: ${parsedResponse.themes ? 'YES (' + parsedResponse.themes.length + ' items)' : 'NO'}`);

  if (!parsedResponse.summary ||
      !parsedResponse.description ||
      !parsedResponse.themes) {
    console.error('❌ Step 5 FAILED: Invalid response structure. Missing required fields.');
    console.error('Has summary:', !!parsedResponse.summary);
    console.error('Has description:', !!parsedResponse.description);
    console.error('Has annotations:', !!parsedResponse.annotations);
    console.error('Has themes:', !!parsedResponse.themes);
    throw new Error('Invalid response structure from AI');
  }

  // Ensure optional fields have fallbacks
  if (!parsedResponse.annotations) {
    console.warn('⚠️ No annotations in response, using empty array');
    parsedResponse.annotations = [];
  }

  if (!parsedResponse.sentiments) {
    console.warn('⚠️ No sentiments in response, using empty array');
    parsedResponse.sentiments = [];
  }

  if (!parsedResponse.keywords) {
    console.warn('⚠️ No keywords in response, using empty array');
    parsedResponse.keywords = [];
  }

  if (parsedResponse.themes.length < 4 || parsedResponse.themes.length > 5) {
    console.warn(`⚠️ Expected 4-5 themes, got ${parsedResponse.themes.length}`);
  }

  console.log('✅ Step 5: Response validation complete');
  console.log(`✅ Step 6: Returning parsed response with ${parsedResponse.themes.length} themes and ${parsedResponse.annotations.length} annotations`);

  return parsedResponse;
}

/**
 * Format ISO8601 date to YYYY-MM-DD
 */
function formatDate(isoDate: string): string {
  try {
    const date = new Date(isoDate);
    return date.toISOString().split('T')[0];
  } catch {
    return isoDate;
  }
}

/**
 * Estimate cost of OpenAI API call
 * gpt-4.1-nano: $0.10 per 1M input tokens, $0.40 per 1M output tokens
 */
function estimateCost(totalTokens: number): string {
  // Rough estimate: assume 60% input, 40% output
  const inputTokens = totalTokens * 0.6;
  const outputTokens = totalTokens * 0.4;
  const cost = (inputTokens / 1_000_000 * 0.10) + (outputTokens / 1_000_000 * 0.40);
  return cost.toFixed(6);
}

/**
 * Create JSON response with CORS headers
 */
function jsonResponse(
  data: InsightsResponse | ErrorResponse,
  status: number
): Response {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
      }
    }
  );
}
