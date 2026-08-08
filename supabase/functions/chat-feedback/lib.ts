// lib.ts
//
// Pure, network-free helpers for the chat-feedback Edge Function, split out so
// the request-validation and toggle logic can be unit-tested with `deno test`
// (index.ts wires these into auth + Supabase I/O).

export type FeedbackType = 'positive' | 'negative';

export interface FeedbackRequest {
  messageId?: string;
  feedbackType?: FeedbackType;
}

export type FeedbackAction = 'delete' | 'update' | 'create';

/**
 * Validates the request body. Returns an error message, or null when valid.
 * `feedbackType` is optional (a DELETE clears feedback regardless of type),
 * but when present it must be one of the two allowed values.
 */
export function validateFeedbackRequest(body: FeedbackRequest | null | undefined): string | null {
  if (!body || !body.messageId) {
    return 'messageId is required';
  }
  if (body.feedbackType && !['positive', 'negative'].includes(body.feedbackType)) {
    return 'feedbackType must be "positive" or "negative"';
  }
  return null;
}

/**
 * Decides the write to perform from the HTTP method, the currently-stored
 * feedback type, and the requested type:
 *  - an explicit DELETE always clears,
 *  - re-submitting the same type toggles it off (delete),
 *  - a different type on existing feedback updates it,
 *  - otherwise a new row is created.
 * The handler still guards the delete path when there is nothing stored.
 */
export function resolveFeedbackAction(
  method: string,
  existingType: string | null | undefined,
  requestedType: string | null | undefined,
): FeedbackAction {
  if (method === 'DELETE') return 'delete';
  // Toggle off when the request matches what's stored — this also covers the
  // both-absent no-op (a POST with no type and no existing row), matching the
  // original `existingFeedback?.feedback_type === feedbackType` condition.
  if ((existingType ?? null) === (requestedType ?? null)) return 'delete';
  if (existingType) return 'update';
  return 'create';
}
