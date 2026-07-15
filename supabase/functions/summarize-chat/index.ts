// index.ts
//
// Edge function: summarize-chat
//
// Summarizes a chat conversation into a journal entry using Gemini.
// Takes the conversation messages and generates a title + content
// that captures the key insights and reflections.
//
// Deploy: supabase functions deploy summarize-chat
//

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { requireAuth } from '../_shared/auth.ts';
import { checkRateLimit, rateLimitedResponse } from '../_shared/rate_limit.ts';

// ============================================================
// CONFIGURATION
// ============================================================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// spec-004 R2: per-user cost guard on this LLM endpoint.
const RATE_LIMIT_MAX_REQUESTS = 10;
const RATE_LIMIT_WINDOW_SECONDS = 60 * 60; // 1 hour

const GEMINI_CHAT_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

const SYSTEM_PROMPT = `You are a journal summarization assistant for Memento.

Transform a user-AI conversation into a concise journal entry.

Guidelines:
- Write in FIRST PERSON as the user's own reflection
- Be direct and specific - state concrete realizations, not vague sentiments
- 1-2 short paragraphs maximum (4-6 sentences total)
- Focus on: what was discussed, what was learned, any decisions or next steps
- Skip flowery language - be clear and actionable
- Do NOT reference "the AI", "our conversation", or the chat itself

Plain text only, no formatting.`;

// ============================================================
// TYPES
// ============================================================

interface SummaryRequest {
  sessionId?: string;
  messages: Array<{
    role: string;
    content: string;
  }>;
}

// ============================================================
// MAIN HANDLER
// ============================================================

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ============================================================
    // 1. AUTHENTICATE
    // ============================================================

    const auth = await requireAuth(req, corsHeaders, { missing: 'AUTH_REQUIRED', invalid: 'AUTH_FAILED' });
    if (auth instanceof Response) return auth;
    const { user, supabase } = auth;

    const rateLimit = await checkRateLimit(
      supabase,
      user.id,
      'summarize-chat',
      RATE_LIMIT_MAX_REQUESTS,
      RATE_LIMIT_WINDOW_SECONDS
    );
    if (!rateLimit.allowed) {
      return rateLimitedResponse(rateLimit, corsHeaders);
    }

    // ============================================================
    // 2. PARSE REQUEST
    // ============================================================

    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, 405);
    }

    let body: SummaryRequest;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'Invalid JSON body' }, 400);
    }

    if (!body.messages || body.messages.length === 0) {
      return jsonResponse({ error: 'Messages are required' }, 400);
    }

    console.log(`📝 Summarize request from user ${user.id.substring(0, 8)}... (${body.messages.length} messages)`);

    // ============================================================
    // 3. BUILD CONVERSATION TEXT
    // ============================================================

    const conversationText = body.messages
      .map(m => {
        const role = m.role === 'user' ? 'User' : 'Assistant';
        // Clean up assistant messages - extract body if JSON
        let content = m.content;
        if (m.role === 'assistant') {
          try {
            const parsed = JSON.parse(content);
            if (parsed.body) {
              content = parsed.body;
            }
          } catch {
            // Not JSON, use as-is
          }
        }
        return `${role}: ${content}`;
      })
      .join('\n\n');

    // ============================================================
    // 4. CALL GEMINI
    // ============================================================

    const geminiApiKey = Deno.env.get('GEMINI_API_KEY');
    if (!geminiApiKey) {
      throw new Error('GEMINI_API_KEY not configured');
    }

    const geminiResponse = await fetch(`${GEMINI_CHAT_URL}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': geminiApiKey },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{
          role: 'user',
          parts: [{ text: `Here is the conversation to summarize:\n\n${conversationText}` }]
        }],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 400,
        },
      }),
    });

    if (!geminiResponse.ok) {
      const errorText = await geminiResponse.text();
      console.error(`Gemini API error: ${geminiResponse.status}`, errorText.substring(0, 500));
      throw new Error(`Gemini API error: ${geminiResponse.status}`);
    }

    const geminiData = await geminiResponse.json();

    // Log usage metadata if present
    if (geminiData.usageMetadata) {
      console.log('Gemini usage_metadata:', JSON.stringify(geminiData.usageMetadata));
    }

    // Extract response text
    const rawText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!rawText) {
      throw new Error('Empty response from Gemini');
    }

    console.log('Gemini raw response:', rawText.substring(0, 200));

    // ============================================================
    // 5. RETURN PLAIN TEXT CONTENT
    // ============================================================

    console.log(`✅ Summary generated (${rawText.length} chars)`);

    return jsonResponse({
      content: rawText.trim()
    }, 200);

  } catch (error) {
    console.error('Summarize function error:', error);
    return jsonResponse({
      error: 'Failed to generate summary',
      message: error instanceof Error ? error.message : 'Unknown error'
    }, 500);
  }
});

// ============================================================
// HELPERS
// ============================================================

function jsonResponse(data: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
