// _shared/auth.ts
//
// Authentication helper functions shared across edge functions
//
// Purpose:
// - Extract and validate JWT tokens from requests
// - Create authenticated Supabase clients
// - Get current user from JWT
// - Return standardized error responses for auth failures
//
// Usage:
// import { authenticateUser, createAuthenticatedClient } from '../_shared/auth.ts'

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Create a Supabase client authenticated with the provided authorization header.
 */
export function createAuthenticatedClient(authHeader: string): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } }
  );
}

/**
 * Authenticate user from request and return user and supabase client.
 * Throws an error if authentication fails.
 */
export async function authenticateUser(req: Request): Promise<{
  user: { id: string; email?: string };
  supabase: SupabaseClient;
}> {
  const authHeader = req.headers.get('Authorization');

  if (!authHeader) {
    throw new Error('Missing authorization header');
  }

  const supabase = createAuthenticatedClient(authHeader);
  const { data: { user }, error } = await supabase.auth.getUser();

  if (error || !user) {
    throw new Error('Unauthorized');
  }

  return { user, supabase };
}

/**
 * Create a standardized auth error response.
 */
export function authErrorResponse(message: string, code = 'AUTH_ERROR'): Response {
  return new Response(
    JSON.stringify({ error: message, code }),
    { status: 401, headers: { 'Content-Type': 'application/json' } }
  );
}
