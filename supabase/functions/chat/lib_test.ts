import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import {
  buildContextBlock,
  buildEffectiveQuery,
  buildGeminiContents,
  buildPreviewExcerpt,
  cleanParsedBody,
  condenseHistoryForRetrieval,
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

Deno.test('buildContextBlock_empty_returnsPlaceholder', () => {
  assertEquals(buildContextBlock([]).block, '[No journal entries matched this topic]');
});

Deno.test('buildContextBlock_formatsEntries', () => {
  const entries: MatchedEntry[] = [
    {
      id: 'a',
      content: 'Hello journal',
      created_at: '2025-06-01T12:00:00.000Z',
      similarity: 0.9,
    },
  ];
  const result = buildContextBlock(entries);
  assertEquals(result.block.includes('[Journal context'), true);
  assertEquals(result.block.includes('Hello journal'), true);
  assertEquals(result.block.includes('[End of journal context]'), true);
});

Deno.test('buildGeminiContents_appendsUserMessageWithContext', () => {
  const history: { role: string; content: string }[] = [];
  const contents = buildGeminiContents(history, '[ctx]', 'Hi');
  assertEquals(contents.length, 1);
  assertEquals(contents[0].role, 'user');
  assertEquals(contents[0].parts[0].text.includes('[ctx]'), true);
  assertEquals(contents[0].parts[0].text.endsWith('Hi'), true);
});

Deno.test('buildGeminiContents_assistantJsonExtractsBody', () => {
  const history = [
    {
      role: 'assistant',
      content: JSON.stringify({ heading1: null, heading2: null, body: 'Only body' }),
    },
  ];
  const contents = buildGeminiContents(history, '[ctx]', 'Next');
  assertEquals(contents[0].role, 'model');
  assertEquals(contents[0].parts[0].text, 'Only body');
});

Deno.test('extractGeminiResponseText_readsCandidateText', () => {
  const text = extractGeminiResponseText({
    candidates: [{ content: { parts: [{ text: '{"body":"x"}' }] } }],
  });
  assertEquals(text, '{"body":"x"}');
});

Deno.test('extractGeminiResponseText_missingFallback', () => {
  const text = extractGeminiResponseText({});
  assertEquals(text.includes('trouble'), true);
});

Deno.test('sanitizeResponseBody_plainTextUnchanged', () => {
  assertEquals(sanitizeResponseBody('hello'), 'hello');
});

Deno.test('sanitizeResponseBody_extractsBodyFromJson', () => {
  const out = sanitizeResponseBody(String.raw`{"body":"Line\none"}`);
  assertEquals(out, 'Line\none');
});

Deno.test('extractBody_prefersStringBody', () => {
  assertEquals(extractBody({ body: '  hi  ' }), 'hi');
});

Deno.test('extractBody_nestedObject', () => {
  assertEquals(extractBody({ body: { text: 'nested' } }), 'nested');
});

Deno.test('cleanParsedBody_unwrapsNestedJson', () => {
  const inner = JSON.stringify({ body: 'final' });
  const outer = JSON.stringify({ body: inner });
  assertEquals(cleanParsedBody({ body: outer }), 'final');
});

Deno.test('buildEffectiveQuery_includes history', () => {
  const history: ChatMessageRow[] = [
    { role: 'user', content: 'stress at work' },
    { role: 'assistant', content: JSON.stringify({ body: 'Tell me more', heading1: null, heading2: null }) },
  ];
  const q = buildEffectiveQuery('last week?', history);
  assertEquals(q.includes('Current:'), true);
  assertEquals(q.includes('last week?'), true);
});

Deno.test('shouldSkipJournalRetrieval_shortQuery', () => {
  assertEquals(shouldSkipJournalRetrieval('hi', 'hi', 10), true);
  assertEquals(shouldSkipJournalRetrieval('x'.repeat(12), 'x'.repeat(12), 10), false);
});

Deno.test('shouldSkipJournalRetrieval_acknowledgements', () => {
  assertEquals(shouldSkipJournalRetrieval('thanks', 'thanks', 4), true);
  assertEquals(shouldSkipJournalRetrieval('ok', 'ok', 4), true);
});

Deno.test('diversifyEntriesForContext_dedupesSimilar', () => {
  const dup = 'same content here'.repeat(3);
  const entries: MatchedEntry[] = [
    { id: 'a', content: dup, created_at: '2025-01-01T00:00:00Z', similarity: 0.9 },
    { id: 'b', content: dup, created_at: '2025-01-02T00:00:00Z', similarity: 0.85 },
    { id: 'c', content: 'different story entirely', created_at: '2025-01-03T00:00:00Z', similarity: 0.8 },
  ];
  const out = diversifyEntriesForContext(entries, 2);
  assertEquals(out.length, 2);
  assertEquals(out.some((e) => e.id === 'c'), true);
});

Deno.test('parseCitedEntryIds_filtersAndTrims', () => {
  assertEquals(
    parseCitedEntryIds({ cited_entry_ids: ['  a1  ', '', 2] as unknown[] }),
    ['a1'],
  );
  assertEquals(parseCitedEntryIds({}), []);
});

Deno.test('filterCitedIdsToAllowed_stripsUnknown', () => {
  const entries: MatchedEntry[] = [
    { id: 'good', content: 'x', created_at: '2025-01-01T00:00:00Z', similarity: 1 },
  ];
  assertEquals(filterCitedIdsToAllowed(['good', 'bad', 'good'], entries), ['good']);
});

Deno.test('buildPreviewExcerpt_keywordWindow', () => {
  const text = 'Intro filler. ' + 'wordmatch '.repeat(20) + ' tail.';
  const ex = buildPreviewExcerpt(text, 'wordmatch', 40);
  assertEquals(ex.includes('wordmatch'), true);
  assertEquals(ex.length <= 45, true);
});

Deno.test('condenseHistoryForRetrieval_respectsMaxChars', () => {
  const long = 'x'.repeat(500);
  const h: ChatMessageRow[] = [{ role: 'user', content: long }];
  const c = condenseHistoryForRetrieval(h, 100);
  assertEquals(c.length <= 100, true);
});
