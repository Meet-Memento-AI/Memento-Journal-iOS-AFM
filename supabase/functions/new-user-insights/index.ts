// new-user-insights/index.ts
//
// Edge function for analyzing user self-reflection text and returning personalized themes
//
// Features:
// - Server-side input validation (20-2000 chars, sanitization)
// - Rate limiting (24h between analyses, unless text changes)
// - Theme caching (static data loaded once)
// - Atomic database save (for rate limiting)
// - Word boundary matching (accurate scoring)
// - Smart theme count (3-6 based on match quality)
//
// Deploy: supabase functions deploy new-user-insights

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { requireAuth } from '../_shared/auth.ts';
import type { Theme, ThemeScore, AnalysisResponse, ErrorResponse } from './types.ts';

// ============================================================
// CONFIGURATION
// ============================================================

// CORS headers - Allow mobile apps (no Origin header required)
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MAX_TEXT_LENGTH = 2000;
const MIN_TEXT_LENGTH = 20;
const MIN_ALPHA_CHARS = 10;
const RATE_LIMIT_HOURS = 24;  // spec-004 R3: re-enabled (was 0 "for testing")

// Theme cache (loaded once, reused across requests)
let themesCache: Theme[] | null = null;

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

    const auth = await requireAuth(req, corsHeaders, { missing: 'AUTH_REQUIRED', invalid: 'AUTH_FAILED' });
    if (auth instanceof Response) return auth;
    const { user, supabase } = auth;

    console.log(`📝 Theme analysis request from user: ${user.id.substring(0, 8)}...`);

    // ============================================================
    // 2. VALIDATE INPUT
    // ============================================================

    if (req.method !== 'POST') {
      return jsonResponse(
        { error: 'Method not allowed', code: 'METHOD_NOT_ALLOWED' },
        405
      );
    }

    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(
        { error: 'Invalid JSON body', code: 'INVALID_JSON' },
        400
      );
    }

    const { selfReflectionText } = body;

    // Validate text exists
    if (!selfReflectionText || typeof selfReflectionText !== 'string') {
      return jsonResponse(
        { error: 'Missing selfReflectionText field', code: 'MISSING_TEXT' },
        400
      );
    }

    // Sanitize HTML tags (prevent XSS)
    const sanitized = selfReflectionText.replaceAll(/<[^>]*>/g, '').trim();

    // Validate length
    if (sanitized.length < MIN_TEXT_LENGTH) {
      return jsonResponse(
        {
          error: `Text must be at least ${MIN_TEXT_LENGTH} characters`,
          code: 'TEXT_TOO_SHORT'
        },
        400
      );
    }

    if (sanitized.length > MAX_TEXT_LENGTH) {
      return jsonResponse(
        {
          error: `Text must be less than ${MAX_TEXT_LENGTH} characters`,
          code: 'TEXT_TOO_LONG'
        },
        413
      );
    }

    // Validate meaningful content
    const alphaCount = (sanitized.match(/[a-zA-Z]/g) || []).length;
    if (alphaCount < MIN_ALPHA_CHARS) {
      return jsonResponse(
        {
          error: 'Text must contain meaningful content',
          code: 'INSUFFICIENT_CONTENT'
        },
        400
      );
    }

    console.log(`✅ Input validated: ${sanitized.length} characters`);

    // ============================================================
    // 3. RATE LIMITING & IDEMPOTENCY CHECK
    // ============================================================

    const { data: profile, error: profileError } = await supabase
      .from('user_profiles')
      .select('themes_analyzed_at, onboarding_self_reflection')
      .eq('user_id', user.id)
      .maybeSingle();

    if (profileError) {
      console.error('Profile fetch error:', profileError);
      return jsonResponse(
        { error: 'Failed to fetch user profile', code: 'PROFILE_ERROR' },
        500
      );
    }

    // Rate limiting (spec-004 R3): re-enabled. Re-analysis is blocked within
    // RATE_LIMIT_HOURS UNLESS the self-reflection text changed materially — that
    // preserves the intended "let users re-run after editing" behavior while
    // stopping unbounded LLM spend from repeated identical requests.
    if (RATE_LIMIT_HOURS > 0 && profile?.themes_analyzed_at) {
      const lastAnalyzed = new Date(profile.themes_analyzed_at).getTime();
      const hoursSince = (Date.now() - lastAnalyzed) / (1000 * 60 * 60);
      const textChanged = profile.onboarding_self_reflection
        ? calculateSimilarity(sanitized, profile.onboarding_self_reflection) < 0.7
        : true;
      if (hoursSince < RATE_LIMIT_HOURS && !textChanged) {
        return jsonResponse(
          {
            error: 'Insights were generated recently. Try again later or edit your reflection.',
            code: 'RATE_LIMITED',
            retryAfter: `${Math.ceil(RATE_LIMIT_HOURS - hoursSince)}h`,
          },
          429
        );
      }
    }

    // ============================================================
    // 4. LOAD THEMES FROM DATABASE (CACHED)
    // ============================================================

    if (!themesCache) {
      console.log('📚 Loading themes from database...');
      const { data: themes, error: themesError } = await supabase
        .from('themes')
        .select('name, title, summary, keywords, emoji, category')
        .order('name');

      if (themesError || !themes || themes.length === 0) {
        console.error('Themes fetch error:', themesError);
        return jsonResponse(
          { error: 'Failed to load themes', code: 'THEMES_ERROR' },
          500
        );
      }

      themesCache = themes as Theme[];
      console.log(`✅ Cached ${themesCache.length} themes`);
    }

    // ============================================================
    // 5. ANALYZE TEXT & SCORE THEMES
    // ============================================================

    const scoredThemes = scoreThemes(sanitized.toLowerCase(), themesCache);

    // Sort by score descending
    scoredThemes.sort((a, b) => b.score - a.score);

    // Log top scores for debugging (no user content!)
    const top3Scores = scoredThemes.slice(0, 3).map(t => `${t.theme.name}(${t.score})`).join(', ');
    console.log(`🎯 Top 3 scores: ${top3Scores}`);

    // ============================================================
    // 6. DETERMINE THEME COUNT (3-6 based on quality)
    // ============================================================

    const themeCount = determineThemeCount(scoredThemes);
    const selectedThemes = scoredThemes.slice(0, themeCount).map(st => st.theme);
    const recommendedCount = Math.max(3, themeCount - 1);

    console.log(`✅ Selected ${themeCount} themes, recommend selecting ${recommendedCount}`);

    // ============================================================
    // 7. SAVE TO DATABASE (CRITICAL: Enables rate limiting)
    // ============================================================

    const analyzedAt = new Date().toISOString();

    const { error: upsertError } = await supabase
      .from('user_profiles')
      .upsert({
        user_id: user.id,
        onboarding_self_reflection: sanitized,
        themes_analyzed_at: analyzedAt
      }, {
        onConflict: 'user_id'
      });

    if (upsertError) {
      console.error('Failed to save analysis:', upsertError);
      // Don't fail the request, but log error
    } else {
      console.log('💾 Saved analysis timestamp to database');
    }

    // ============================================================
    // 8. RETURN RESPONSE
    // ============================================================

    const response: AnalysisResponse = {
      themes: selectedThemes,
      recommendedCount,
      analyzedAt,
      themeCount
    };

    // Log the response structure for debugging
    console.log('📤 Sending response:', JSON.stringify({
      themesCount: selectedThemes.length,
      recommendedCount,
      themeCount,
      firstTheme: selectedThemes[0]?.name
    }));

    return jsonResponse(response, 200);

  } catch (error) {
    // ============================================================
    // ERROR HANDLING
    // ============================================================

    // Log full error server-side
    console.error('❌ Unexpected error:', error);

    // Return generic error to client (no stack traces or sensitive info)
    return jsonResponse(
      {
        error: 'Analysis failed. Please try again.',
        code: 'INTERNAL_ERROR'
      },
      500
    );
  }
});

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Score themes based on keyword matches in text
 * Uses word boundaries for accurate matching
 */
function scoreThemes(text: string, themes: Theme[]): ThemeScore[] {
  const firstSentence = text.split(/[.!?]/)[0].toLowerCase();

  return themes.map(theme => {
    let score = 0;
    const matchedKeywords: string[] = [];

    for (const keyword of theme.keywords) {
      const keywordLower = keyword.toLowerCase();

      // Use word boundaries to avoid false positives
      // Example: "work" matches "work", "working", but not "homework"
      const pattern = new RegExp(String.raw`\b` + escapeRegex(keywordLower) + String.raw`\w*\b`, 'gi');
      const matches = text.match(pattern);
      const occurrences = matches ? matches.length : 0;

      if (occurrences > 0) {
        matchedKeywords.push(keyword);
        score += occurrences;  // +1 per match

        // Bonus for first sentence (+1)
        if (pattern.exec(firstSentence)) {
          score += 1;
        }
      }
    }

    // Bonus if theme name appears in text (+2)
    const themeName = theme.name.replace('-', ' ');
    if (text.includes(themeName)) {
      score += 2;
    }

    return { theme, score, matchedKeywords };
  });
}

/**
 * Determine how many themes to return (3-6) based on match quality
 */
function determineThemeCount(scoredThemes: ThemeScore[]): number {
  const strongMatches = scoredThemes.filter(t => t.score >= 5).length;
  const mediumMatches = scoredThemes.filter(t => t.score >= 3).length;

  // Return 6 if: 4+ very strong matches (score 5+)
  if (strongMatches >= 4) return 6;

  // Return 5 if: 3+ strong matches OR 5+ medium matches
  if (strongMatches >= 3 || mediumMatches >= 5) return 5;

  // Return 4 if: 2+ strong matches OR 3+ medium matches
  if (strongMatches >= 2 || mediumMatches >= 3) return 4;

  // Return 3 minimum (even for weak/general input)
  return 3;
}

/**
 * Calculate similarity between two texts (Jaccard index)
 * Used for rate limiting - allow re-analysis if text changes significantly
 */
function calculateSimilarity(text1: string, text2: string): number {
  const words1 = new Set(text1.toLowerCase().split(/\s+/));
  const words2 = new Set(text2.toLowerCase().split(/\s+/));

  const intersection = new Set([...words1].filter(w => words2.has(w)));
  const union = new Set([...words1, ...words2]);

  return intersection.size / union.size;
}

/**
 * Escape special regex characters
 */
function escapeRegex(str: string): string {
  return str.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);
}

/**
 * Create JSON response with CORS headers
 */
function jsonResponse(
  data: AnalysisResponse | ErrorResponse,
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
