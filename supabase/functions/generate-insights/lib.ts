// lib.ts
//
// Pure, network-free helpers for the generate-insights Edge Function, split out
// so entry validation, date/cost formatting, and the model-response parsing can
// be unit-tested with `deno test`. index.ts keeps the auth, cache, and OpenAI
// I/O and delegates these bits here.

import type { JournalEntry, OpenAIInsightResponse } from './types.ts';

export const MAX_ENTRIES = 20;
export const MIN_ENTRIES = 1;
export const MAX_CONTENT_LENGTH = 500;

export interface EntryValidationError {
  error: string;
  code: string;
}

/**
 * Validates the entries array from the request body. Returns an
 * {error, code} object, or null when the entries are acceptable.
 */
export function validateEntries(entries: unknown): EntryValidationError | null {
  if (!entries || !Array.isArray(entries)) {
    return { error: 'Missing or invalid entries array', code: 'MISSING_ENTRIES' };
  }
  if (entries.length < MIN_ENTRIES) {
    return { error: `Need at least ${MIN_ENTRIES} entry`, code: 'INVALID_ENTRIES' };
  }
  if (entries.length > MAX_ENTRIES) {
    return { error: `Maximum ${MAX_ENTRIES} entries allowed`, code: 'TOO_MANY_ENTRIES' };
  }
  for (const entry of entries) {
    if (!entry || typeof entry.content !== 'string' || entry.content.trim().length === 0) {
      return { error: 'All entries must have content', code: 'EMPTY_CONTENT' };
    }
  }
  return null;
}

/** Formats an ISO8601 date to YYYY-MM-DD, returning the input on parse failure. */
export function formatDate(isoDate: string): string {
  try {
    const date = new Date(isoDate);
    const out = date.toISOString().split('T')[0];
    return out;
  } catch {
    return isoDate;
  }
}

/**
 * Estimates OpenAI cost (gpt-4.1-nano: $0.10/1M input, $0.40/1M output),
 * assuming a 60/40 input/output split. Returns a fixed-6 dollar string.
 */
export function estimateCost(totalTokens: number): string {
  const inputTokens = totalTokens * 0.6;
  const outputTokens = totalTokens * 0.4;
  const cost = (inputTokens / 1_000_000 * 0.1) + (outputTokens / 1_000_000 * 0.4);
  return cost.toFixed(6);
}

/**
 * Parses the model's response text into an object. If a straight JSON.parse
 * fails (the model wrapped the JSON in prose), falls back to extracting the
 * outermost {...} span. Throws when neither yields valid JSON.
 */
export function extractInsightJson(responseText: string): OpenAIInsightResponse {
  try {
    return JSON.parse(responseText) as OpenAIInsightResponse;
  } catch {
    const firstBrace = responseText.indexOf('{');
    const lastBrace = responseText.lastIndexOf('}');
    if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
      return JSON.parse(responseText.substring(firstBrace, lastBrace + 1)) as OpenAIInsightResponse;
    }
    throw new Error(
      `Invalid JSON response from AI. First 200 chars: ${responseText.substring(0, 200)}`,
    );
  }
}

/**
 * Enforces the required fields (summary, description, themes) and backfills the
 * optional array fields so the caller always sees a well-formed shape. Throws
 * on a structurally invalid response. Mutates and returns `parsed`.
 */
export function validateAndNormalizeInsight(parsed: OpenAIInsightResponse): OpenAIInsightResponse {
  if (!parsed.summary || !parsed.description || !parsed.themes) {
    throw new Error('Invalid response structure from AI');
  }
  parsed.annotations = parsed.annotations ?? [];
  parsed.sentiments = parsed.sentiments ?? [];
  parsed.keywords = parsed.keywords ?? [];
  return parsed;
}

/** Builds the token-optimized entries payload sent to the model. */
export function buildEntriesData(entries: JournalEntry[]): {
  entries: Array<{ date: string; title: string; content: string; word_count: number; mood: string }>;
} {
  return {
    entries: entries.map((entry) => ({
      date: formatDate(entry.date),
      title: entry.title || 'Untitled',
      content: entry.content.substring(0, MAX_CONTENT_LENGTH),
      word_count: entry.word_count,
      mood: entry.mood || 'neutral',
    })),
  };
}
