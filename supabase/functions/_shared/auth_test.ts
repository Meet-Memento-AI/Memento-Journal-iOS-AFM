import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { authErrorResponse, requireAuth } from './auth.ts';

const cors = { 'Access-Control-Allow-Origin': '*' };

Deno.test('requireAuth_missingHeader_returns401WithCode', async () => {
  const req = new Request('https://example.com/fn', { method: 'POST' });
  const result = await requireAuth(req, cors, { missing: 'AUTH_REQUIRED', invalid: 'AUTH_FAILED' });
  if (!(result instanceof Response)) throw new Error('expected a Response');
  assertEquals(result.status, 401);
  const body = await result.json();
  assertEquals(body, { error: 'Missing authorization header', code: 'AUTH_REQUIRED' });
});

Deno.test('requireAuth_missingHeader_noCodeGiven_omitsCode', async () => {
  const req = new Request('https://example.com/fn', { method: 'POST' });
  const result = await requireAuth(req, cors);
  if (!(result instanceof Response)) throw new Error('expected a Response');
  const body = await result.json();
  assertEquals(body, { error: 'Missing authorization header' });
});

Deno.test('authErrorResponse_includesCorsHeaders', () => {
  const res = authErrorResponse('Unauthorized', cors, 'AUTH_FAILED');
  assertEquals(res.status, 401);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), '*');
  assertEquals(res.headers.get('Content-Type'), 'application/json');
});

Deno.test('authErrorResponse_withoutCode_omitsCodeKey', async () => {
  const res = authErrorResponse('Unauthorized', cors);
  const body = await res.json();
  assertEquals('code' in body, false);
});
