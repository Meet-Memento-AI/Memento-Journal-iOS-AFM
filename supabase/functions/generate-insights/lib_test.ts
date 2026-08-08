// lib_test.ts — unit tests for generate-insights pure helpers.
// Run: deno test --allow-read supabase/functions/generate-insights/lib_test.ts

import { assertEquals, assertThrows } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import {
  estimateCost,
  extractInsightJson,
  formatDate,
  MAX_ENTRIES,
  validateAndNormalizeInsight,
  validateEntries,
} from './lib.ts';
import type { OpenAIInsightResponse } from './types.ts';

Deno.test('validateEntries: rejects missing/non-array', () => {
  assertEquals(validateEntries(undefined)?.code, 'MISSING_ENTRIES');
  assertEquals(validateEntries(null)?.code, 'MISSING_ENTRIES');
  assertEquals(validateEntries('nope')?.code, 'MISSING_ENTRIES');
});

Deno.test('validateEntries: rejects empty array and over-limit', () => {
  assertEquals(validateEntries([])?.code, 'INVALID_ENTRIES');
  const tooMany = Array.from({ length: MAX_ENTRIES + 1 }, () => ({ content: 'x' }));
  assertEquals(validateEntries(tooMany)?.code, 'TOO_MANY_ENTRIES');
});

Deno.test('validateEntries: rejects blank content', () => {
  assertEquals(validateEntries([{ content: '   ' }])?.code, 'EMPTY_CONTENT');
  assertEquals(validateEntries([{ content: 'ok' }, { content: '' }])?.code, 'EMPTY_CONTENT');
});

Deno.test('validateEntries: accepts a valid set', () => {
  assertEquals(validateEntries([{ content: 'a real entry' }]), null);
});

Deno.test('formatDate: ISO to YYYY-MM-DD, passthrough on garbage', () => {
  assertEquals(formatDate('2026-01-03T10:30:00Z'), '2026-01-03');
  assertEquals(formatDate('not-a-date'), 'not-a-date');
});

Deno.test('estimateCost: deterministic 60/40 split', () => {
  assertEquals(estimateCost(0), '0.000000');
  // 1M tokens → 600k in * $0.10/1M + 400k out * $0.40/1M = 0.06 + 0.16 = 0.22
  assertEquals(estimateCost(1_000_000), '0.220000');
});

Deno.test('extractInsightJson: parses clean JSON', () => {
  const obj = extractInsightJson('{"summary":"s","description":"d","themes":[]}');
  assertEquals(obj.summary, 's');
});

Deno.test('extractInsightJson: recovers JSON wrapped in prose', () => {
  const wrapped = 'Here is your insight:\n{"summary":"s","description":"d","themes":[]}\nThanks!';
  const obj = extractInsightJson(wrapped);
  assertEquals(obj.description, 'd');
});

Deno.test('extractInsightJson: throws when no JSON present', () => {
  assertThrows(() => extractInsightJson('completely non-JSON text'));
});

Deno.test('validateAndNormalizeInsight: backfills optional arrays', () => {
  const parsed = {
    summary: 's',
    description: 'd',
    themes: [{ name: 't', icon: '📊', explanation: 'e', frequency: '3 times', source_entries: [] }],
  } as unknown as OpenAIInsightResponse;
  const out = validateAndNormalizeInsight(parsed);
  assertEquals(out.annotations, []);
  assertEquals(out.sentiments, []);
  assertEquals(out.keywords, []);
});

Deno.test('validateAndNormalizeInsight: throws on missing required fields', () => {
  assertThrows(() => validateAndNormalizeInsight({ summary: 's' } as unknown as OpenAIInsightResponse));
  assertThrows(() => validateAndNormalizeInsight({ description: 'd', themes: [] } as unknown as OpenAIInsightResponse));
});
