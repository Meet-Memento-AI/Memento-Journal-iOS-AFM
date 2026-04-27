// index.ts
//
// Edge function for Memento journaling companion chat
//
// Uses Google Gemini with explicit context caching:
// - Base Memento system prompt + personalization cached
// - Journal entries cached (large, static context)
// - Conversation messages sent each request (dynamic)
//
// See: https://ai.google.dev/gemini-api/docs/caching
// Deploy: supabase functions deploy chat-with-entries
//

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type {
  ChatWithEntriesRequest,
  ChatResponse,
  JournalEntryPayload,
  SystemPromptContext,
  ErrorResponse
} from './types.ts';

// ============================================================
// CONFIGURATION
// ============================================================

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const GEMINI_MODEL = 'gemini-2.5-flash';
const CACHE_TTL_SECONDS = 3600; // 1 hour per Gemini best practices
const MAX_ENTRIES = 30;
const MAX_CONTENT_LENGTH = 600;

// ============================================================
// SYSTEM PROMPT LOADER (from system_prompt.md)
// ============================================================

interface ParsedPrompt {
  base: string;
  onboardingBlock: string;
  goalsBlock: string;
}

let cachedPrompt: ParsedPrompt | null = null;

const FALLBACK_BASE_PROMPT = `You are Memento, a journaling companion. You help users explore their journal entries to discover patterns and understand themselves.

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

Every response should leave the user feeling heard, curious about themselves, and glad they journaled.`;

async function loadSystemPrompt(): Promise<ParsedPrompt> {
  if (cachedPrompt) return cachedPrompt;

  try {
    const url = new URL('./system_prompt.md', import.meta.url);
    const raw = await Deno.readTextFile(url);
    const [basePart, templatePart] = raw.split('<!-- PERSONALIZATION_TEMPLATE -->').map(s => s.trim());
    const base = (basePart ?? '').replace(/^#\s+Memento\s+System\s+Prompt\s*\n?/i, '').trim() || FALLBACK_BASE_PROMPT;

    const extractBlock = (content: string, start: string, end: string): string => {
      if (!content) return '';
      const s = content.indexOf(start);
      const e = content.indexOf(end);
      if (s === -1 || e === -1) return '';
      return content.slice(s + start.length, e).trim();
    };

    cachedPrompt = {
      base: base || FALLBACK_BASE_PROMPT,
      onboardingBlock: extractBlock(
        templatePart ?? '',
        '<!-- ONBOARDING_REFLECTION_BLOCK -->',
        '<!-- END_ONBOARDING_REFLECTION_BLOCK -->'
      ),
      goalsBlock: extractBlock(
        templatePart ?? '',
        '<!-- SELECTED_GOALS_BLOCK -->',
        '<!-- END_SELECTED_GOALS_BLOCK -->'
      )
    };
    return cachedPrompt;
  } catch (err) {
    console.warn('Failed to load system_prompt.md, using fallback:', err);
    cachedPrompt = {
      base: FALLBACK_BASE_PROMPT,
      onboardingBlock: 'PERSONALIZATION (from user\'s onboarding):\nThe user shared during onboarding: "{{onboarding_reflection}}"\nUse this to guide your attention when exploring their entries.',
      goalsBlock: 'JOURNALING GOALS (user-selected themes to explore):\nThe user chose to focus on: {{selected_goals}}\nWhen relevant, connect insights to these goals.'
    };
    return cachedPrompt;
  }
}

function buildSystemPrompt(ctx: SystemPromptContext | undefined, parsed: ParsedPrompt): string {
  const reflection = ctx?.onboardingSelfReflection?.trim();
  const goals = ctx?.selectedGoals?.map(g => g.trim()).filter(Boolean) ?? [];

  const parts: string[] = [];
  if (reflection && parsed.onboardingBlock) {
    parts.push(parsed.onboardingBlock.replace(/\{\{onboarding_reflection\}\}/g, reflection));
  }
  if (goals.length && parsed.goalsBlock) {
    parts.push(parsed.goalsBlock.replace(/\{\{selected_goals\}\}/g, goals.join(', ')));
  }

  if (parts.length === 0) return parsed.base;
  return `${parsed.base}\n\n---\n${parts.join('\n\n')}`;
}

// ============================================================
// JOURNAL CONTEXT
// ============================================================

function formatEntriesForContext(entries: JournalEntryPayload[]): string {
  const truncated = entries.slice(0, MAX_ENTRIES).map(e => ({
    date: e.date,
    title: e.title || 'Untitled',
    content: e.content.substring(0, MAX_CONTENT_LENGTH)
  }));
  return JSON.stringify(truncated, null, 2);
}

async function sha256(input: string): Promise<string> {
  const enc = new TextEncoder();
  const data = enc.encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

/** Compute stable hash for cache key — entries must match exactly to reuse cache */
async function computeEntriesHash(entries: JournalEntryPayload[]): Promise<string> {
  const canonical = entries
    .map(e => `${e.date}|${e.title || ''}|${e.content?.substring(0, 200) || ''}`)
    .sort()
    .join('\n');
  return sha256(canonical);
}

/** Compute hash of systemPromptContext — different personalization = different cache */
function computeContextHash(ctx: SystemPromptContext | undefined): string {
  const ref = ctx?.onboardingSelfReflection?.trim() ?? '';
  const goals = (ctx?.selectedGoals ?? []).map(g => g.trim()).filter(Boolean).sort();
  return ref + '|' + goals.join(',');
}

/** Merge client payload with user_profiles so onboarding personalization applies even if the client omitted it or raced the fetch. */
function mergeSystemPromptContext(
  fromBody: SystemPromptContext | undefined,
  fromDb: { onboarding_self_reflection: string | null; selected_goals: string[] | null } | null
): SystemPromptContext | undefined {
  const dbReflection = fromDb?.onboarding_self_reflection?.trim() ?? '';
  const dbGoals = (fromDb?.selected_goals ?? []).map(g => g.trim()).filter(Boolean);

  const bodyReflection = fromBody?.onboardingSelfReflection?.trim() ?? '';
  const bodyGoals = (fromBody?.selectedGoals ?? []).map(g => g.trim()).filter(Boolean);

  const reflection = bodyReflection.length > 0 ? bodyReflection : dbReflection;
  const goals = bodyGoals.length > 0 ? bodyGoals : dbGoals;

  if (!reflection && goals.length === 0) return undefined;
  return {
    onboardingSelfReflection: reflection || undefined,
    selectedGoals: goals.length > 0 ? goals : undefined
  };
}

// ============================================================
// GEMINI API HELPERS
// ============================================================

async function createCache(
  apiKey: string,
  systemPrompt: string,
  entriesText: string
): Promise<{ name: string; expireTime?: string }> {
  const url = `${GEMINI_BASE}/cachedContents?key=${apiKey}`;
  const body = {
    model: `models/${GEMINI_MODEL}`,
    systemInstruction: {
      parts: [{ text: systemPrompt }]
    },
    contents: [
      {
        role: 'user',
        parts: [{
          text: `JOURNAL ENTRIES (context for this conversation — reference by date when citing):\n${entriesText}`
        }]
      }
    ],
    ttl: `${CACHE_TTL_SECONDS}s`
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini cache create failed: ${res.status} ${err}`);
  }
  const data = await res.json();
  return { name: data.name, expireTime: data.expireTime };
}

async function generateWithCache(
  apiKey: string,
  cacheName: string,
  messages: { content: string; isFromUser: string }[]
): Promise<string> {
  const contents = messages.map(m => ({
    role: m.isFromUser === 'true' ? 'user' : 'model',
    parts: [{ text: m.content }]
  }));

  const url = `${GEMINI_BASE}/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
  const body = {
    cachedContent: cacheName,
    contents,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 800
    }
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini generate failed: ${res.status} ${err}`);
  }
  const data = await res.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
  if (!text) {
    throw new Error('Empty or invalid response from Gemini');
  }
  return text;
}

async function generateWithoutCache(
  apiKey: string,
  systemPrompt: string,
  entriesText: string,
  messages: { content: string; isFromUser: string }[]
): Promise<string> {
  const fullSystem = `${systemPrompt}\n\n---\nJOURNAL ENTRIES (context for this conversation — reference by date when citing):\n${entriesText}`;
  const contents = [
    { role: 'user', parts: [{ text: fullSystem }] },
    ...messages.map(m => ({
      role: m.isFromUser === 'true' ? 'user' : 'model',
      parts: [{ text: m.content }]
    }))
  ];

  const url = `${GEMINI_BASE}/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
  const body = {
    contents,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 800
    }
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini generate failed: ${res.status} ${err}`);
  }
  const data = await res.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
  if (!text) {
    throw new Error('Empty or invalid response from Gemini');
  }
  return text;
}

// ============================================================
// MAIN HANDLER
// ============================================================

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse({ error: 'Missing authorization header', code: 'AUTH_REQUIRED' }, 401);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return jsonResponse({ error: 'Unauthorized', code: 'AUTH_FAILED' }, 401);
    }

    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) {
      return jsonResponse({ error: 'GEMINI_API_KEY not configured', code: 'CONFIG_ERROR' }, 500);
    }

    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed', code: 'INVALID_METHOD' }, 405);
    }

    let body: ChatWithEntriesRequest;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'Invalid JSON body', code: 'INVALID_JSON' }, 400);
    }

    const { messages, entries, systemPromptContext: systemPromptContextFromBody } = body;

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return jsonResponse({ error: 'Messages array required and must not be empty', code: 'MISSING_MESSAGES' }, 400);
    }

    if (!entries || !Array.isArray(entries)) {
      return jsonResponse({ error: 'Entries array required', code: 'MISSING_ENTRIES' }, 400);
    }

    const validEntries = entries
      .filter(e => e?.content?.trim())
      .map(e => ({
        date: e.date || 'unknown',
        title: e.title || 'Untitled',
        content: (e.content || '').substring(0, MAX_CONTENT_LENGTH),
        word_count: e.word_count ?? 0
      }));

    const { data: profileRow } = await supabase
      .from('user_profiles')
      .select('onboarding_self_reflection, selected_goals')
      .eq('user_id', user.id)
      .maybeSingle();

    const systemPromptContext = mergeSystemPromptContext(systemPromptContextFromBody, profileRow);

    const parsed = await loadSystemPrompt();
    const systemPrompt = buildSystemPrompt(systemPromptContext, parsed);
    const entriesText = formatEntriesForContext(validEntries);
    const entriesHash = await computeEntriesHash(validEntries);
    const contextHash = computeContextHash(systemPromptContext);
    const cacheKey = await sha256(entriesHash + '|' + contextHash);

    // Check for valid cache (Gemini context caching)
    const now = new Date().toISOString();
    const { data: cached } = await supabase
      .from('user_chat_caches')
      .select('cache_name')
      .eq('user_id', user.id)
      .eq('entries_hash', cacheKey)
      .gt('expires_at', now)
      .limit(1)
      .maybeSingle();

    let cacheName: string | null = cached?.cache_name ?? null;

    if (!cacheName) {
      try {
        const cache = await createCache(apiKey, systemPrompt, entriesText);
        cacheName = cache.name;
        const expiresAt = cache.expireTime ?? new Date(Date.now() + CACHE_TTL_SECONDS * 1000).toISOString();
        await supabase.from('user_chat_caches').upsert(
          {
            user_id: user.id,
            cache_name: cacheName,
            entries_hash: cacheKey,
            expires_at: expiresAt
          },
          { onConflict: 'user_id,entries_hash' }
        );
      } catch (cacheErr) {
        // Fallback: cache may fail if below min tokens (1024 for Gemini 2.5 Flash)
        console.warn('Cache create failed, using uncached request:', cacheErr);
        cacheName = null;
      }
    }

    const responseText = cacheName
      ? await generateWithCache(apiKey, cacheName, messages)
      : await generateWithoutCache(apiKey, systemPrompt, entriesText, messages);

    const chatResponse: ChatResponse = {
      body: responseText
    };

    return jsonResponse(chatResponse, 200);
  } catch (error) {
    console.error('chat-with-entries error:', error);
    const msg = error instanceof Error ? error.message : 'Unknown error';
    if (msg.includes('429') || msg.includes('resource exhausted')) {
      return jsonResponse(
        { error: 'Too many requests. Please try again in a few minutes.', code: 'RATE_LIMIT' },
        429
      );
    }
    return jsonResponse(
      { error: 'Failed to generate response. Please try again.', code: 'INTERNAL_ERROR' },
      500
    );
  }
});

function jsonResponse(data: ChatResponse | ErrorResponse, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}
