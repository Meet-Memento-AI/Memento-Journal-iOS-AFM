// _shared/rate_limit.ts  (spec-004 R2)
//
// Per-user, per-function sliding-window rate limiting backed by the
// public.rate_limits table (see migration 20260714000000_add_rate_limits.sql).
//
// FAIL-OPEN: any error (missing table, network, RLS) ALLOWS the request. Rate
// limiting is a cost guard, not a correctness gate — it must never take a
// working AI feature offline. Abuse is bounded; an outage would be worse.
//
// The table is RLS'd to `auth.uid() = user_id`, so pass the SAME user-scoped
// client the function already built from the caller's Authorization header —
// no service-role key required.

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds?: number;
  remaining?: number;
}

/**
 * @param client       user-scoped Supabase client (caller's JWT)
 * @param userId       authenticated user id
 * @param functionName logical bucket, e.g. "chat"
 * @param maxRequests  allowed requests per window
 * @param windowSeconds sliding window length
 */
export async function checkRateLimit(
  client: SupabaseClient,
  userId: string,
  functionName: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  try {
    const sinceIso = new Date(Date.now() - windowSeconds * 1000).toISOString();

    const { count, error } = await client
      .from('rate_limits')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('function_name', functionName)
      .gte('created_at', sinceIso);

    if (error) {
      console.warn(`[rate_limit] fail-open (count error): ${error.message}`);
      return { allowed: true };
    }

    const used = count ?? 0;
    if (used >= maxRequests) {
      return { allowed: false, retryAfterSeconds: windowSeconds, remaining: 0 };
    }

    // Record this request (best-effort; ignore write errors — still fail-open).
    const { error: insertError } = await client
      .from('rate_limits')
      .insert({ user_id: userId, function_name: functionName });
    if (insertError) {
      console.warn(`[rate_limit] insert failed (allowing): ${insertError.message}`);
    }

    return { allowed: true, remaining: Math.max(0, maxRequests - used - 1) };
  } catch (e) {
    console.warn(`[rate_limit] fail-open (exception): ${e instanceof Error ? e.message : String(e)}`);
    return { allowed: true };
  }
}

/** Standard 429 body for a blocked request. */
export function rateLimitedResponse(
  result: RateLimitResult,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      error: 'Rate limit exceeded. Please slow down and try again shortly.',
      code: 'RATE_LIMITED',
      retry_after_seconds: result.retryAfterSeconds ?? 3600,
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Retry-After': String(result.retryAfterSeconds ?? 3600),
      },
    },
  );
}
