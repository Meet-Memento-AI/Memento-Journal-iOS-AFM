// _shared/auth.ts  (spec-004 R5)
//
// The single JWT verifier every edge function uses. Every LLM/chat function
// previously duplicated this same ~15-line block inline; this is that block,
// extracted so a future function can't copy a subtly wrong variant.
//
// Usage:
//   import { requireAuth } from '../_shared/auth.ts'
//   const auth = await requireAuth(req, corsHeaders, { missing: 'AUTH_REQUIRED', invalid: 'AUTH_FAILED' });
//   if (auth instanceof Response) return auth;
//   const { user, supabase } = auth;
//
// sync-embedding does NOT use this helper — it runs with the service-role key
// and accepts either a shared webhook secret or a user JWT, which is a
// genuinely different auth mode (see its own inline comment).

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface AuthenticatedUser {
  id: string;
  email?: string;
}

export interface AuthContext {
  user: AuthenticatedUser;
  supabase: SupabaseClient;
}

/**
 * Create a Supabase client authenticated with the caller's Authorization header.
 */
export function createAuthenticatedClient(authHeader: string): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } }
  );
}

/**
 * Verify the caller's JWT. Returns the user + a client scoped to their
 * Authorization header on success, or a ready-to-return 401 Response on failure.
 */
export async function requireAuth(
  req: Request,
  corsHeaders: Record<string, string>,
  codes: { missing?: string; invalid?: string } = {}
): Promise<AuthContext | Response> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return authErrorResponse('Missing authorization header', corsHeaders, codes.missing);
  }

  const supabase = createAuthenticatedClient(authHeader);
  const { data: { user }, error } = await supabase.auth.getUser();

  if (error || !user) {
    console.error('Auth error:', error);
    return authErrorResponse('Unauthorized', corsHeaders, codes.invalid);
  }

  return { user, supabase };
}

/**
 * Standardized 401 response. `code` is omitted from the body when not given,
 * matching functions that don't use error codes.
 */
export function authErrorResponse(
  message: string,
  corsHeaders: Record<string, string>,
  code?: string
): Response {
  const body: Record<string, unknown> = { error: message };
  if (code) body.code = code;
  return new Response(JSON.stringify(body), {
    status: 401,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
