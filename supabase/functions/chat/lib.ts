// Pure helpers for chat Edge Function (unit-tested without Gemini / Supabase).

export interface MatchedEntry {
  id: string;
  content: string;
  created_at: string;
  similarity: number;
}

export interface ChatMessageRow {
  role: string;
  content: string;
}

export interface ContextBlockResult {
  block: string;
  indexMap: Map<number, string>;
}

export function buildContextBlock(entries: MatchedEntry[]): ContextBlockResult {
  if (entries.length === 0) {
    return {
      block: '[No journal entries matched this topic]',
      indexMap: new Map(),
    };
  }

  const indexMap = new Map<number, string>();
  const formatted = entries.map((e, idx) => {
    const refNum = idx + 1;
    indexMap.set(refNum, e.id);
    const date = new Date(e.created_at);
    const label = date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
    return `[${label}] ${e.content}`;
  });

  const block = [
    '[Journal context — reference entries by date in your response]',
    '',
    ...formatted,
    '',
    '[End of journal context]',
  ].join('\n');

  return { block, indexMap };
}

export function buildGeminiContents(
  history: ChatMessageRow[],
  contextBlock: string,
  currentMessage: string,
): Array<{ role: string; parts: Array<{ text: string }> }> {
  const contents: Array<{ role: string; parts: Array<{ text: string }> }> = [];

  for (const msg of history) {
    let content = msg.content;

    if (msg.role === 'assistant') {
      try {
        const parsed = JSON.parse(msg.content);
        if (parsed.body) {
          content = parsed.body;
        }
      } catch {
        // Not JSON (legacy message), use as-is
      }
    }

    contents.push({
      role: msg.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: content }],
    });
  }

  contents.push({
    role: 'user',
    parts: [{ text: `${contextBlock}\n\n${currentMessage}` }],
  });

  return contents;
}

/** First text part from Gemini generateContent JSON response. */
export function extractGeminiResponseText(data: unknown): string {
  const d = data as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const text = d.candidates?.[0]?.content?.parts?.[0]?.text;
  return typeof text === 'string' && text.length > 0
    ? text
    : "I'm having trouble connecting right now. Please try again in a moment.";
}

/**
 * Sanitizes response body to ensure users never see raw JSON.
 * Falls back gracefully if body extraction fails.
 */
export function sanitizeResponseBody(text: string): string {
  const trimmed = text.trim();

  // If it doesn't look like JSON, return as-is
  if (!trimmed.startsWith('{')) {
    return text;
  }

  // Try to parse as JSON first
  try {
    const parsed = JSON.parse(trimmed);
    if (typeof parsed.body === 'string' && parsed.body.trim()) {
      return parsed.body.trim();
    }
    // Check other common fields
    if (typeof parsed.response === 'string' && parsed.response.trim()) {
      return parsed.response.trim();
    }
    if (typeof parsed.text === 'string' && parsed.text.trim()) {
      return parsed.text.trim();
    }
    if (typeof parsed.message === 'string' && parsed.message.trim()) {
      return parsed.message.trim();
    }
    if (typeof parsed.content === 'string' && parsed.content.trim()) {
      return parsed.content.trim();
    }
  } catch {
    // JSON parse failed, try regex patterns
  }

  // Regex fallback patterns
  const patterns = [
    /"body"\s*:\s*"((?:[^"\\]|\\.)*)"/,
    /"body"\s*:\s*'((?:[^'\\]|\\.)*)'/,
    /body:\s*["']([^"']+)["']/,
  ];

  for (const pattern of patterns) {
    const match = pattern.exec(trimmed);
    if (match) {
      return match[1]
        .replaceAll(String.raw`\"`, '"')
        .replaceAll(String.raw`\n`, '\n')
        .replaceAll(String.raw`\t`, '\t');
    }
  }

  // Last resort: if it looks like JSON but we can't extract body,
  // return the raw text minus the JSON wrapper (better than error message)
  console.warn('sanitizeResponseBody: Could not extract body, returning cleaned text');

  // Try to extract any meaningful text content
  const textContent = trimmed
    .replaceAll(/^\{|\}$/g, '')  // Remove outer braces
    .replaceAll(/"[^"]+"\s*:\s*/g, '')  // Remove JSON keys
    .replaceAll(/[{}[\]]/g, '')  // Remove remaining brackets
    .replaceAll(/,\s*$/g, '')  // Remove trailing commas
    .replaceAll(String.raw`\n`, '\n')
    .replaceAll(String.raw`\"`, '"')
    .trim();

  if (textContent.length > 10) {
    return textContent;
  }

  return "I'm processing your request. Please try again.";
}

/**
 * Cleans parsed body by unwrapping nested JSON and sanitizing.
 */
export function cleanParsedBody(parsed: { body?: unknown }): string {
  // Handle non-string body types
  if (typeof parsed.body !== 'string') {
    // If body is an object, try to extract text from it
    if (parsed.body && typeof parsed.body === 'object') {
      const bodyObj = parsed.body as Record<string, unknown>;
      if (typeof bodyObj.text === 'string') return bodyObj.text;
      if (typeof bodyObj.content === 'string') return bodyObj.content;
      // Convert to string as last resort
      return JSON.stringify(parsed.body);
    }
    console.warn('cleanParsedBody: body is not a string:', typeof parsed.body);
    return "I'm processing your request. Please try again.";
  }

  let bodyText: string = parsed.body;

  // Unwrap nested JSON if present
  let attempts = 0;
  while (bodyText.trim().startsWith('{') && attempts < 3) {
    try {
      const nested = JSON.parse(bodyText);
      if (typeof nested.body === 'string' && nested.body.trim()) {
        bodyText = nested.body;
      } else if (typeof nested.text === 'string' && nested.text.trim()) {
        bodyText = nested.text;
      } else if (typeof nested.content === 'string' && nested.content.trim()) {
        bodyText = nested.content;
      } else {
        break;
      }
    } catch {
      break;
    }
    attempts++;
  }

  // If body is empty, provide a graceful fallback
  if (!bodyText.trim()) {
    return "I'm processing your request. Please try again.";
  }

  // If still looks like JSON, try to sanitize it
  if (bodyText.trim().startsWith('{')) {
    return sanitizeResponseBody(bodyText);
  }

  return bodyText;
}

/**
 * Extracts a usable body string from parsed response.
 */
/** Condense recent turns for embedding / retrieval (current message not included). */
export function condenseHistoryForRetrieval(
  history: ChatMessageRow[],
  maxChars = 1200,
): string {
  if (history.length === 0) return '';
  const tail = history.slice(-10);
  const parts: string[] = [];
  let used = 0;
  for (const m of tail) {
    let t = m.content;
    if (m.role === 'assistant') {
      try {
        const p = JSON.parse(m.content) as { body?: string };
        if (typeof p.body === 'string') t = p.body;
      } catch {
        // legacy plain text
      }
    }
    t = t.replaceAll(/\s+/g, ' ').trim();
    if (t.length > 400) t = t.slice(0, 400) + '...';
    const piece = `${m.role === 'user' ? 'User' : 'Assistant'}: ${t}`;
    if (used + piece.length > maxChars) break;
    parts.push(piece);
    used += piece.length + 1;
  }
  return parts.join('\n');
}

/** User message + optional condensed history for follow-ups (“what about last week?”). */
export function buildEffectiveQuery(userMessage: string, history: ChatMessageRow[]): string {
  const h = condenseHistoryForRetrieval(history);
  const u = userMessage.trim();
  if (!h) return u;
  return `${h}\n\nCurrent: ${u}`;
}

/** Skip vector retrieval when grounding is unlikely to help. */
export function shouldSkipJournalRetrieval(
  effectiveQuery: string,
  userMessage: string,
  minLen: number,
): boolean {
  const q = effectiveQuery.trim();
  if (q.length < minLen) return true;

  const lower = userMessage.trim().toLowerCase();

  // Only skip PURE acknowledgements (exact match, no additional content)
  const pureAck = /^(thanks|thank you|thx|ty|ok|okay|got it|cool|nice|great|perfect|sounds good)\.?$/i;
  if (pureAck.test(lower) && lower.length < 20) return true;

  // Only skip pure meta questions (exact match)
  const pureMeta = /^(what can you do\??|who are you\??|help)$/i;
  if (pureMeta.test(lower)) return true;

  return false;
}

/** Keep top entries by similarity while reducing near-duplicate bodies. */
export function diversifyEntriesForContext(
  entries: MatchedEntry[],
  max: number,
): MatchedEntry[] {
  if (entries.length <= max) return entries;
  const sorted = [...entries].sort((a, b) => b.similarity - a.similarity);
  const out: MatchedEntry[] = [];
  const norm = (s: string) => s.slice(0, 200).toLowerCase().replaceAll(/\s+/g, ' ');
  for (const e of sorted) {
    if (out.length >= max) break;
    const n = norm(e.content);
    const dup = out.some((o) => {
      const m = norm(o.content);
      let same = 0;
      const L = Math.min(n.length, m.length);
      for (let i = 0; i < L; i++) {
        if (n[i] === m[i]) same++;
      }
      return L > 20 && same / L > 0.95;
    });
    if (!dup) out.push(e);
  }
  // Fill remaining slots
  for (const e of sorted) {
    if (out.length >= max) break;
    if (!out.some((x) => x.id === e.id)) out.push(e);
  }
  return out.slice(0, max);
}

export function parseCitedEntryIds(parsed: Record<string, unknown>): string[] {
  const raw = parsed.cited_entry_ids;
  if (!Array.isArray(raw)) return [];
  return raw.filter((x): x is string => typeof x === 'string' && x.trim().length > 0).map((s) => s.trim());
}

/** Only IDs present in this turn's journal context. */
export function filterCitedIdsToAllowed(
  citedIds: string[],
  entries: MatchedEntry[],
): string[] {
  const allowed = new Set(entries.map((e) => e.id));
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of citedIds) {
    if (!allowed.has(id)) continue;
    if (seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

/** Short excerpt: window around query term overlap, else start of entry. */
export function buildPreviewExcerpt(
  content: string,
  query: string,
  maxLen = 120,
): string {
  const text = content.replaceAll(/\s+/g, ' ').trim();
  if (text.length <= maxLen) return text;
  const words = query.toLowerCase().split(/\s+/).filter((w) => w.length > 2);
  const lower = text.toLowerCase();
  let idx = -1;
  for (const w of words) {
    const j = lower.indexOf(w);
    if (j >= 0) {
      idx = j;
      break;
    }
  }
  if (idx < 0) return text.slice(0, maxLen) + '…';
  const half = Math.floor(maxLen / 2);
  const start = Math.max(0, idx - half);
  const slice = text.slice(start, start + maxLen);
  return (start > 0 ? '…' : '') + slice + (start + maxLen < text.length ? '…' : '');
}

export function extractBody(parsed: Record<string, unknown>): string | null {
  if (typeof parsed.body === 'string' && parsed.body.trim()) {
    return parsed.body.trim();
  }

  if (parsed.body && typeof parsed.body === 'object') {
    const bodyObj = parsed.body as Record<string, unknown>;
    if (typeof bodyObj.text === 'string' && bodyObj.text.trim()) {
      return bodyObj.text.trim();
    }
    if (typeof bodyObj.content === 'string' && bodyObj.content.trim()) {
      return bodyObj.content.trim();
    }
  }

  if (typeof parsed.response === 'string' && parsed.response.trim()) {
    return parsed.response.trim();
  }

  if (typeof parsed.text === 'string' && parsed.text.trim()) {
    return parsed.text.trim();
  }

  if (typeof parsed.message === 'string' && parsed.message.trim()) {
    return parsed.message.trim();
  }

  return null;
}

/**
 * Calculates a dynamic RAG threshold based on user feedback patterns.
 * If user has been giving mostly negative feedback, lower the threshold
 * to cast a wider net and retrieve more diverse entries.
 */
export function calculateDynamicThreshold(
  baseThreshold: number,
  positiveCount: number,
  negativeCount: number,
): number {
  const total = positiveCount + negativeCount;

  // Not enough data to make adjustments
  if (total < 5) return baseThreshold;

  const negativeRatio = negativeCount / total;

  // High negative ratio (>40%): user is unhappy - cast wider net
  if (negativeRatio > 0.4) {
    return Math.max(0.25, baseThreshold - 0.1);
  }

  // High positive ratio (>70%): current behavior is working well
  // Keep the base threshold
  return baseThreshold;
}
