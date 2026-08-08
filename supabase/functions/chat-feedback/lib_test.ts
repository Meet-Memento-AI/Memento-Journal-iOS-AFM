// lib_test.ts — unit tests for chat-feedback pure helpers.
// Run: deno test --allow-read supabase/functions/chat-feedback/lib_test.ts

import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { resolveFeedbackAction, validateFeedbackRequest } from './lib.ts';

Deno.test('validateFeedbackRequest: missing body or messageId is rejected', () => {
  assertEquals(validateFeedbackRequest(null), 'messageId is required');
  assertEquals(validateFeedbackRequest(undefined), 'messageId is required');
  assertEquals(validateFeedbackRequest({}), 'messageId is required');
  assertEquals(validateFeedbackRequest({ feedbackType: 'positive' }), 'messageId is required');
});

Deno.test('validateFeedbackRequest: invalid feedbackType is rejected', () => {
  assertEquals(
    validateFeedbackRequest({ messageId: 'm1', feedbackType: 'meh' as unknown as 'positive' }),
    'feedbackType must be "positive" or "negative"',
  );
});

Deno.test('validateFeedbackRequest: valid requests pass', () => {
  assertEquals(validateFeedbackRequest({ messageId: 'm1' }), null); // type optional (clear)
  assertEquals(validateFeedbackRequest({ messageId: 'm1', feedbackType: 'positive' }), null);
  assertEquals(validateFeedbackRequest({ messageId: 'm1', feedbackType: 'negative' }), null);
});

Deno.test('resolveFeedbackAction: explicit DELETE always deletes', () => {
  assertEquals(resolveFeedbackAction('DELETE', 'positive', 'positive'), 'delete');
  assertEquals(resolveFeedbackAction('DELETE', undefined, undefined), 'delete');
  assertEquals(resolveFeedbackAction('DELETE', 'negative', 'positive'), 'delete');
});

Deno.test('resolveFeedbackAction: re-submitting the stored type toggles off', () => {
  assertEquals(resolveFeedbackAction('POST', 'positive', 'positive'), 'delete');
  assertEquals(resolveFeedbackAction('POST', 'negative', 'negative'), 'delete');
});

Deno.test('resolveFeedbackAction: a different type updates existing feedback', () => {
  assertEquals(resolveFeedbackAction('POST', 'positive', 'negative'), 'update');
  assertEquals(resolveFeedbackAction('POST', 'negative', 'positive'), 'update');
});

Deno.test('resolveFeedbackAction: no existing feedback creates', () => {
  assertEquals(resolveFeedbackAction('POST', undefined, 'positive'), 'create');
  assertEquals(resolveFeedbackAction('POST', null, 'negative'), 'create');
});

Deno.test('resolveFeedbackAction: POST with no type and no existing row is a delete no-op', () => {
  // Matches the original `existingFeedback?.feedback_type === feedbackType`
  // both-absent branch — the handler then returns a deleted no-op.
  assertEquals(resolveFeedbackAction('POST', undefined, undefined), 'delete');
  assertEquals(resolveFeedbackAction('POST', null, undefined), 'delete');
});
