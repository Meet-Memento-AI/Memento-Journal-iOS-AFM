// index.ts
//
// Edge function: chat
//
// RAG chatbot endpoint. The iOS app sends a user message. This
// function embeds the question, retrieves similar journal entries
// via pgvector, builds a prompt with that context, calls Gemini
// 2.5 Flash, persists the conversation, and returns the response.
//
// System prompt: ./MEMENTO_SYSTEM_PROMPT.md (see docs/prompts/MEMENTO_SYSTEM_PROMPT.md).
// Optional explicit context caching: https://ai.google.dev/gemini-api/docs/caching
// Env: GEMINI_API_KEY (required), GEMINI_SYSTEM_CACHE_NAME (optional cachedContents/... id).
//
// Deploy: supabase functions deploy chat
//

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { requireAuth } from '../_shared/auth.ts';
import { checkRateLimit, rateLimitedResponse } from '../_shared/rate_limit.ts';
import {
  buildContextBlock,
  buildGeminiContents,
  buildEffectiveQuery,
  buildPreviewExcerpt,
  calculateDynamicThreshold,
  cleanParsedBody,
  diversifyEntriesForContext,
  extractBody,
  extractGeminiResponseText,
  filterCitedIdsToAllowed,
  parseCitedEntryIds,
  sanitizeResponseBody,
  shouldSkipJournalRetrieval,
  type MatchedEntry,
  type ChatMessageRow,
} from './lib.ts';

// ============================================================
// CONFIGURATION
// ============================================================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// spec-004 R2: per-user cost guard on this LLM endpoint.
const RATE_LIMIT_MAX_REQUESTS = 30;
const RATE_LIMIT_WINDOW_SECONDS = 60 * 60; // 1 hour

const GEMINI_EMBEDDING_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent';

const GEMINI_CHAT_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

const GEMINI_CACHED_CONTENTS_URL =
  'https://generativelanguage.googleapis.com/v1beta/cachedContents';

/** Source of truth on disk: ./MEMENTO_SYSTEM_PROMPT.md (duplicate of docs/prompts/MEMENTO_SYSTEM_PROMPT.md). */
const SYSTEM_PROMPT_PATH = new URL('./MEMENTO_SYSTEM_PROMPT.md', import.meta.url);

/** In-memory cache resource name for explicit context caching (see https://ai.google.dev/gemini-api/docs/caching). */
let geminiSystemCacheName: string | null | undefined = undefined;

const SYSTEM_PROMPT_FALLBACK = `You are Memento, a journaling companion. Help users explore their journal entries with warmth and curiosity. Respond with JSON only: {"heading1":null,"heading2":null,"body":"...","cited_entry_ids":[]} — use cited_entry_ids only for UUIDs from the journal context block, or []. Never fabricate journal content.`;

const HISTORY_LIMIT = 6; // 3 conversation turns is sufficient with RAG context

function chatMatchCount(): number {
  const n = Number.parseInt(Deno.env.get('CHAT_MATCH_COUNT') ?? '10', 10);
  return Number.isFinite(n) && n > 0 ? Math.min(n, 20) : 10;
}

function chatMatchThreshold(): number {
  const n = Number.parseFloat(Deno.env.get('CHAT_MATCH_THRESHOLD') ?? '0.4');
  return Number.isFinite(n) && n > 0 && n < 1 ? n : 0.4;
}

function chatContextMaxEntries(): number {
  const n = Number.parseInt(Deno.env.get('CHAT_CONTEXT_MAX_ENTRIES') ?? '7', 10);
  return Number.isFinite(n) && n > 0 ? Math.min(n, 15) : 7;
}

function chatMaxCitations(): number {
  const n = Number.parseInt(Deno.env.get('CHAT_MAX_CITATIONS') ?? '3', 10);
  return Number.isFinite(n) && n >= 0 ? Math.min(n, 10) : 3;
}

function chatMinQueryLen(): number {
  const n = Number.parseInt(Deno.env.get('CHAT_MIN_QUERY_LEN') ?? '10', 10);
  return Number.isFinite(n) && n >= 0 ? Math.min(n, 50) : 10;
}

// JSON schema for structured responses (simplified: no inline citations)
const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    heading1: { type: "string", nullable: true },
    heading2: { type: "string", nullable: true },
    body: { type: "string" },
    cited_entry_ids: {
      type: "array",
      items: { type: "string" },
      nullable: true,
    },
  },
  required: ["body"],
};

let cachedSystemPromptText: string | null = null;

async function loadSystemPrompt(): Promise<string> {
  if (cachedSystemPromptText) return cachedSystemPromptText;
  try {
    cachedSystemPromptText = await Deno.readTextFile(SYSTEM_PROMPT_PATH);
    return cachedSystemPromptText;
  } catch (e) {
    console.warn('Failed to read MEMENTO_SYSTEM_PROMPT.md:', e);
    cachedSystemPromptText = SYSTEM_PROMPT_FALLBACK;
    return cachedSystemPromptText;
  }
}

function logGeminiUsage(data: unknown): void {
  const meta = (data as { usageMetadata?: Record<string, unknown> })?.usageMetadata;
  if (meta && Object.keys(meta).length > 0) {
    console.log('Gemini usage_metadata:', JSON.stringify(meta));
  }
}

async function createGeminiSystemCache(
  apiKey: string,
  systemPromptText: string,
): Promise<string | null> {
  const body: Record<string, unknown> = {
    model: 'models/gemini-2.5-flash',
    displayName: 'memento-chat-system',
    systemInstruction: {
      role: 'system',
      parts: [{ text: systemPromptText }],
    },
    ttl: '86400s',
  };

  const res = await fetch(`${GEMINI_CACHED_CONTENTS_URL}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const t = await res.text();
    console.warn(`Gemini cachedContents create failed (${res.status}): ${t.substring(0, 800)}`);
    return null;
  }

  const json = (await res.json()) as { name?: string; usageMetadata?: Record<string, unknown> };
  logGeminiUsage(json);
  if (!json.name) return null;
  console.log('✅ Gemini system prompt cache created:', json.name);
  return json.name;
}

async function resolveSystemCacheName(apiKey: string, systemPromptText: string): Promise<string | null> {
  const envName = Deno.env.get('GEMINI_SYSTEM_CACHE_NAME')?.trim();
  if (envName) return envName;

  if (geminiSystemCacheName === null) return null;
  if (typeof geminiSystemCacheName === 'string') return geminiSystemCacheName;

  const created = await createGeminiSystemCache(apiKey, systemPromptText);
  geminiSystemCacheName = created;
  return created;
}

type GeminiContent = Array<{ role: string; parts: Array<{ text: string }> }>;

async function generateGeminiChat(
  apiKey: string,
  systemPromptText: string,
  contents: GeminiContent,
): Promise<{ ok: boolean; data?: unknown; errorText?: string }> {
  const generationConfig = {
    temperature: 0.7,
    maxOutputTokens: 900,
    responseMimeType: 'application/json',
    responseSchema: RESPONSE_SCHEMA,
  };

  const tryWithCache = async (cacheName: string) => {
    const res = await fetch(`${GEMINI_CHAT_URL}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify({
        cachedContent: cacheName,
        contents,
        generationConfig,
      }),
    });
    const errorText = res.ok ? undefined : await res.text();
    const data = res.ok ? await res.json() : undefined;
    if (res.ok && data) logGeminiUsage(data);
    return { res, data, errorText };
  };

  let cacheName = await resolveSystemCacheName(apiKey, systemPromptText);

  if (cacheName) {
    let { res, data, errorText } = await tryWithCache(cacheName);

    if (res.ok && data) {
      return { ok: true, data };
    }

    const expired =
      res.status === 404 ||
      (errorText?.includes('NOT_FOUND') ?? false) ||
      (errorText?.includes('not found') ?? false);
    const usingEnvCache = Boolean(Deno.env.get('GEMINI_SYSTEM_CACHE_NAME')?.trim());
    if (expired && !usingEnvCache) {
      console.warn('Gemini cache miss or expired; recreating cache');
      geminiSystemCacheName = undefined;
      const newName = await createGeminiSystemCache(apiKey, systemPromptText);
      geminiSystemCacheName = newName;
      if (newName) {
        ({ res, data, errorText } = await tryWithCache(newName));
        if (res.ok && data) {
          return { ok: true, data };
        }
      }
    } else if (expired && usingEnvCache) {
      console.warn('GEMINI_SYSTEM_CACHE_NAME expired or invalid; falling back to inline system_instruction');
    }

    console.warn('Gemini cached generateContent failed; falling back to inline system_instruction:', res.status, errorText?.substring(0, 400));
  }

  const res = await fetch(`${GEMINI_CHAT_URL}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: systemPromptText }] },
      contents,
      generationConfig,
    }),
  });

  if (!res.ok) {
    return { ok: false, errorText: await res.text() };
  }

  const data = await res.json();
  logGeminiUsage(data);
  return { ok: true, data };
}

// ============================================================
// TYPES
// ============================================================

interface ChatRequest {
  message: string;
  sessionId?: string;
}

interface GeminiEmbeddingResponse {
  embedding: { values: number[] };
}

interface ChatSource {
  id: string;
  created_at: string;
  preview: string;
}

interface StructuredReply {
  heading1: string | null;
  heading2: string | null;
  body: string;
  /** Journal entry UUIDs this reply draws on; only these become client `sources`. */
  cited_entry_ids: string[];
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

    // ============================================================
    // 1b. RATE LIMIT (spec-004 R2)
    // ============================================================

    const rateLimit = await checkRateLimit(
      supabase,
      user.id,
      'chat',
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

    let body: ChatRequest;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'Invalid JSON body' }, 400);
    }

    const userMessage = body.message?.trim();
    if (!userMessage) {
      return jsonResponse({ error: 'Message is required' }, 400);
    }

    console.log(`💬 Chat request from user ${user.id.substring(0, 8)}...`);

    // ============================================================
    // 3. SESSION HANDLING
    // ============================================================

    let sessionId: string;

    if (body.sessionId) {
      // Validate session belongs to user
      const { data: existingSession, error: sessionError } = await supabase
        .from('chat_sessions')
        .select('id')
        .eq('id', body.sessionId)
        .eq('user_id', user.id)
        .single();

      if (sessionError || !existingSession) {
        console.error('Session validation error:', sessionError);
        return jsonResponse({ error: 'Invalid session', code: 'INVALID_SESSION' }, 400);
      }
      sessionId = existingSession.id;
    } else {
      // Create new session with first message as title (truncated)
      const sessionTitle = userMessage.substring(0, 100);
      const { data: newSession, error: createError } = await supabase
        .from('chat_sessions')
        .insert({ user_id: user.id, title: sessionTitle })
        .select('id')
        .single();

      if (createError || !newSession) {
        console.error('Session creation error:', createError);
        return jsonResponse({ error: 'Failed to create session', code: 'SESSION_ERROR' }, 500);
      }
      sessionId = newSession.id;
      console.log(`📝 Created new session: ${sessionId.substring(0, 8)}...`);
    }

    // ============================================================
    // 5. LOAD CONVERSATION HISTORY (before retrieval — needed for effectiveQuery)
    // ============================================================

    const { data: historyRows } = await supabase
      .from('chat_messages')
      .select('role, content')
      .eq('user_id', user.id)
      .eq('session_id', sessionId)
      .order('created_at', { ascending: true })
      .limit(HISTORY_LIMIT);

    const history: ChatMessageRow[] = historyRows ?? [];

    const effectiveQuery = buildEffectiveQuery(userMessage, history);
    const minQueryLen = chatMinQueryLen();
    const skipRetrieval = shouldSkipJournalRetrieval(effectiveQuery, userMessage, minQueryLen);

    // ============================================================
    // 6. EMBED + RETRIEVE (strategic: effective query, thresholds, diversify)
    // ============================================================

    const geminiApiKey = Deno.env.get('GEMINI_API_KEY');
    if (!geminiApiKey) {
      throw new Error('GEMINI_API_KEY not configured');
    }

    let entries: MatchedEntry[] = [];

    // Calculate dynamic threshold based on user feedback
    let dynamicThreshold = chatMatchThreshold();
    const twoWeeksAgo = new Date(Date.now() - 14 * 86400000).toISOString();

    const { data: feedbackStats } = await supabase
      .from('chat_feedback')
      .select('feedback_type')
      .eq('user_id', user.id)
      .gte('created_at', twoWeeksAgo);

    if (feedbackStats && feedbackStats.length > 0) {
      const positiveCount = feedbackStats.filter(
        (f: { feedback_type: string }) => f.feedback_type === 'positive'
      ).length;
      const negativeCount = feedbackStats.filter(
        (f: { feedback_type: string }) => f.feedback_type === 'negative'
      ).length;

      dynamicThreshold = calculateDynamicThreshold(
        chatMatchThreshold(),
        positiveCount,
        negativeCount
      );

      console.log(`📊 Feedback: ${positiveCount}/${positiveCount + negativeCount} positive, threshold adjusted to ${dynamicThreshold}`);
    }

    if (skipRetrieval) {
      const lower = userMessage.trim().toLowerCase();
      let reason: string;
      if (effectiveQuery.length < minQueryLen) {
        reason = 'short_query';
      } else if (/^(thanks|ok|got it)/.test(lower)) {
        reason = 'acknowledgement';
      } else {
        reason = 'meta_question';
      }
      console.log(`📝 Skipping retrieval: query="${effectiveQuery.slice(0, 50)}" len=${effectiveQuery.length} reason=${reason}`);
    } else {
      console.log(`🔍 RAG query: "${effectiveQuery.slice(0, 100)}..." (${effectiveQuery.length} chars)`);

      const embedMax = Number.parseInt(Deno.env.get('CHAT_EMBED_MAX_CHARS') ?? '2000', 10);
      const embedText = effectiveQuery.slice(0, Number.isFinite(embedMax) ? embedMax : 2000);
      const queryEmbedding = await generateEmbedding(embedText, geminiApiKey);

      const vectorLiteral = `[${queryEmbedding.join(',')}]`;

      const { data: matchedEntries, error: rpcError } = await supabase.rpc('match_journal_entries', {
        query_embedding: vectorLiteral,
        match_user_id: user.id,
        match_count: chatMatchCount(),
        match_threshold: dynamicThreshold,
      });

      if (rpcError) {
        console.error('RPC error:', rpcError);
      }

      const raw = (matchedEntries ?? []) as MatchedEntry[];
      entries = diversifyEntriesForContext(raw, chatContextMaxEntries());
      console.log(`📚 RAG: ${raw.length} raw → ${entries.length} after diversify (threshold=${dynamicThreshold})`);
    }

    // ============================================================
    // 8. BUILD CONTEXT BLOCK
    // ============================================================

    const { block: contextBlock } = buildContextBlock(entries);

    // ============================================================
    // 9. ASSEMBLE & CALL GEMINI 2.5 FLASH
    // ============================================================

    const geminiContents = buildGeminiContents(history, contextBlock, userMessage);

    const systemPrompt = await loadSystemPrompt();
    const geminiResult = await generateGeminiChat(geminiApiKey, systemPrompt, geminiContents);

    let structuredReply: StructuredReply;

    if (!geminiResult.ok || !geminiResult.data) {
      const errText = geminiResult.errorText ?? 'unknown error';
      console.error(`Gemini API error: ${errText}`);
      structuredReply = {
        heading1: null,
        heading2: null,
        body: "I'm having trouble connecting right now. Please try again in a moment.",
        cited_entry_ids: [],
      };
    } else {
      const rawText = extractGeminiResponseText(geminiResult.data);

      // Debug logging: capture raw Gemini response for diagnosing fallback issues
      console.log('Gemini raw response:', rawText.substring(0, 500));

      // Parse JSON response with robust fallback
      try {
        const parsed = JSON.parse(rawText);

        // Try multiple strategies to extract body
        const extractedBody = extractBody(parsed);

        const parsedRec = parsed as Record<string, unknown>;
        const citedIds = parseCitedEntryIds(parsedRec);

        // Use cited_entry_ids from LLM, or fallback to all retrieved entries
        const finalCitedIds = citedIds.length > 0 ? citedIds : entries.map((e) => e.id);

        if (extractedBody) {
          // Clean up body (unwrap nested JSON if needed)
          const cleanedBody = cleanParsedBody({ body: extractedBody });
          structuredReply = {
            heading1: (parsed.heading1 as string | null) || null,
            heading2: (parsed.heading2 as string | null) || null,
            body: cleanedBody,
            cited_entry_ids: finalCitedIds,
          };
        } else {
          // JSON parsed but no usable body found - log and use raw text as body
          console.warn('No body extracted from parsed response:', JSON.stringify(parsed).substring(0, 300));
          // Last resort: try to use the raw text itself if it doesn't look like JSON
          structuredReply = {
            heading1: null,
            heading2: null,
            body: sanitizeResponseBody(rawText),
            cited_entry_ids: [],
          };
        }
      } catch {
        // JSON parsing failed - sanitize rawText
        structuredReply = {
          heading1: null,
          heading2: null,
          body: sanitizeResponseBody(rawText),
          cited_entry_ids: [],
        };
      }
    }

    // ============================================================
    // 10. BUILD SOURCES FROM CITED ENTRY IDS
    // ============================================================

    const maxCit = chatMaxCitations();
    const allowedSourceIds = filterCitedIdsToAllowed(
      structuredReply.cited_entry_ids,
      entries,
    ).slice(0, maxCit);
    const sources: ChatSource[] = allowedSourceIds.map((id) => {
      const e = entries.find((x) => x.id === id);
      if (!e) return null;
      return {
        id: e.id,
        created_at: e.created_at,
        preview: buildPreviewExcerpt(e.content, effectiveQuery),
      };
    }).filter((x): x is ChatSource => x !== null);

    // ============================================================
    // 11. PERSIST MESSAGES
    // ============================================================

    // Store full JSON structure for assistant messages to preserve headings and sources when loading history
    const assistantContent = JSON.stringify({
      heading1: structuredReply.heading1,
      heading2: structuredReply.heading2,
      body: structuredReply.body,
      cited_entry_ids: structuredReply.cited_entry_ids,
      sources: sources,  // Persist full sources for citation display in history
    });

    const { error: insertError } = await supabase.from('chat_messages').insert([
      { user_id: user.id, role: 'user', content: userMessage, session_id: sessionId },
      { user_id: user.id, role: 'assistant', content: assistantContent, session_id: sessionId },
    ]);

    if (insertError) {
      console.error('Failed to persist messages:', insertError);
    }

    // ============================================================
    // 12. RETURN RESPONSE
    // ============================================================

    return jsonResponse({
      reply: structuredReply.body,
      heading1: structuredReply.heading1,
      heading2: structuredReply.heading2,
      cited_entry_ids: structuredReply.cited_entry_ids,
      sources,
      sessionId,
    }, 200);

  } catch (error) {
    console.error('❌ Chat function error:', error);
    return jsonResponse(
      {
        reply: "I'm having trouble connecting right now. Please try again in a moment.",
        cited_entry_ids: [],
        sources: [],
      },
      200
    );
  }
});

// ============================================================
// HELPERS
// ============================================================

async function generateEmbedding(text: string, apiKey: string): Promise<number[]> {
  const response = await fetch(`${GEMINI_EMBEDDING_URL}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify({
      model: 'models/gemini-embedding-001',
      content: { parts: [{ text }] },
      outputDimensionality: 768,
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Embedding API error ${response.status}: ${errText}`);
  }

  const data: GeminiEmbeddingResponse = await response.json();
  const values = data.embedding?.values;
  if (!values || values.length < 768) {
    throw new Error(`Unexpected embedding dimensions: ${values?.length ?? 0}`);
  }
  // Use first 768 dimensions if outputDimensionality was ignored (e.g., 3072 from gemini-embedding-001)
  return values.length === 768 ? values : values.slice(0, 768);
}

function jsonResponse(data: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
