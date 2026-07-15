import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { checkRateLimit, rateLimitedResponse } from './rate_limit.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/** Minimal fake of the `.from(table).select().eq().eq().gte()` / `.insert()` chain rate_limit.ts uses. */
function fakeClient(opts: {
  count?: number | null;
  selectError?: { message: string } | null;
  insertError?: { message: string } | null;
  throwOnFrom?: boolean;
}): SupabaseClient {
  const chain = {
    eq() {
      return chain;
    },
    gte() {
      return Promise.resolve({ count: opts.count ?? 0, error: opts.selectError ?? null });
    },
  };

  return {
    from(_table: string) {
      if (opts.throwOnFrom) {
        throw new Error('connection refused');
      }
      return {
        select() {
          return chain;
        },
        insert() {
          return Promise.resolve({ error: opts.insertError ?? null });
        },
      };
    },
  } as unknown as SupabaseClient;
}

Deno.test('checkRateLimit_underLimit_allows', async () => {
  const client = fakeClient({ count: 2 });
  const result = await checkRateLimit(client, 'user-1', 'chat', 5, 3600);
  assertEquals(result.allowed, true);
  assertEquals(result.remaining, 2); // 5 - 2 - 1 (this request)
});

Deno.test('checkRateLimit_atLimit_blocks', async () => {
  const client = fakeClient({ count: 5 });
  const result = await checkRateLimit(client, 'user-1', 'chat', 5, 3600);
  assertEquals(result.allowed, false);
  assertEquals(result.remaining, 0);
  assertEquals(result.retryAfterSeconds, 3600);
});

Deno.test('checkRateLimit_overLimit_blocks', async () => {
  const client = fakeClient({ count: 9 });
  const result = await checkRateLimit(client, 'user-1', 'chat', 5, 3600);
  assertEquals(result.allowed, false);
});

Deno.test('checkRateLimit_selectError_failsOpen', async () => {
  const client = fakeClient({ selectError: { message: 'db unreachable' } });
  const result = await checkRateLimit(client, 'user-1', 'chat', 5, 3600);
  assertEquals(result.allowed, true);
});

Deno.test('checkRateLimit_insertError_stillAllows', async () => {
  const client = fakeClient({ count: 0, insertError: { message: 'write failed' } });
  const result = await checkRateLimit(client, 'user-1', 'chat', 5, 3600);
  assertEquals(result.allowed, true);
});

Deno.test('checkRateLimit_thrownException_failsOpen', async () => {
  const client = fakeClient({ throwOnFrom: true });
  const result = await checkRateLimit(client, 'user-1', 'chat', 5, 3600);
  assertEquals(result.allowed, true);
});

Deno.test('rateLimitedResponse_returns429WithRetryAfterHeader', async () => {
  const res = rateLimitedResponse({ allowed: false, retryAfterSeconds: 60 }, { 'X-Test': '1' });
  assertEquals(res.status, 429);
  assertEquals(res.headers.get('Retry-After'), '60');
  assertEquals(res.headers.get('X-Test'), '1');
  const body = await res.json();
  assertEquals(body.code, 'RATE_LIMITED');
  assertEquals(body.retry_after_seconds, 60);
});
