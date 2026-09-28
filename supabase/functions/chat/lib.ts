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
  /** Maps citation number (1-based) → entry UUID. */
  indexMap: Map<number, string>;
}

export interface ResolvedCitation {
  ref: number;
  entryId: string;
  theme: string;
}

export function buildContextBlock(entries: MatchedEntry[]): ContextBlockResult {
  if (entries.length === 0) {
    return {
      block: '[No journal entries matched this topic]',
      indexMap: new Map(),
    };
  }

  const indexMap = new Map<number, string>();
  const formatted = entries.map((e, i) => {
    const num = i + 1;
    indexMap.set(num, e.id);
    const date = new Date(e.created_at);
    const label = date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
    return `[${num}] [${label}] ${e.content}`;
  });

  const block = [
    '[Journal context — use [N] inline when referencing a specific entry]',
    '',
    ...formatted,
    '',
    '[End of journal context]',
  ].join('\n');

  return { block, indexMap };
}

/** Resolve model's citation refs against the indexMap, filtering out invalid refs. */
export function resolveInlineCitations(
  citations: Array<{ ref: number; theme: string }> | null | undefined,
  indexMap: Map<number, string>,
): ResolvedCitation[] {
  if (!citations || !Array.isArray(citations)) return [];
  const seen = new Set<number>();
  return citations
    .filter((c) => {
      if (typeof c.ref !== 'number' || !indexMap.has(c.ref)) return false;
      if (seen.has(c.ref)) return false;
      seen.add(c.ref);
      return true;
    })
    .map((c) => ({
      ref: c.ref,
      entryId: indexMap.get(c.ref)!,
      theme: typeof c.theme === 'string' ? c.theme.trim() : '',
    }));
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
 */
export function sanitizeResponseBody(text: string): string {
  const trimmed = text.trim();

  if (!trimmed.startsWith('{')) {
    return text;
  }

  const patterns = [
    /"body"\s*:\s*"((?:[^"\\]|\\.)*)"/,
    /"body"\s*:\s*'((?:[^'\\]|\\.)*)'/,
    /body:\s*["']([^"']+)["']/,
  ];

  for (const pattern of patterns) {
    const match = trimmed.match(pattern);
    if (match) {
      return match[1]
        .replace(/\\"/g, '"')
        .replace(/\\n/g, '\n')
        .replace(/\\t/g, '\t');
    }
  }

  console.warn('sanitizeResponseBody: Could not extract body from JSON-like text');
  return "I had trouble formulating a response. Could you try rephrasing your question?";
}

/**
 * Cleans parsed body by unwrapping nested JSON and sanitizing.
 */
export function cleanParsedBody(parsed: { body?: unknown }): string {
  if (typeof parsed.body !== 'string') {
    console.warn('cleanParsedBody: body is not a string:', typeof parsed.body);
    return "I had trouble formulating a response. Please try again.";
  }

  let bodyText: string = parsed.body;

  let attempts = 0;
  while (bodyText.trim().startsWith('{') && attempts < 3) {
    try {
      const nested = JSON.parse(bodyText);
      if (typeof nested.body === 'string' && nested.body.trim()) {
        bodyText = nested.body;
      } else {
        break;
      }
    } catch {
      break;
    }
    attempts++;
  }

  if (!bodyText.trim()) {
    return "I had trouble formulating a response. Please try again.";
  }

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
  maxChars = 600,
): string {
  if (history.length === 0) return '';
  const tail = history.slice(-6);
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
    t = t.replace(/\s+/g, ' ').trim();
    if (t.length > 220) t = t.slice(0, 220) + '…';
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
  const ack = /^(thanks|thank you|thx|ty|ok+|okay|got it|cool|nice|great|perfect|sounds good)\.?$/i;
  if (ack.test(lower)) return true;
  const meta = /^(what can you do|who are you|help|hi|hello|hey)\.?$/i;
  if (meta.test(lower) && lower.length < 40) return true;
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
  const norm = (s: string) => s.slice(0, 160).toLowerCase().replace(/\s+/g, ' ');
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
      return L > 20 && same / L > 0.88;
    });
    if (!dup) out.push(e);
  }
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
  const text = content.replace(/\s+/g, ' ').trim();
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
