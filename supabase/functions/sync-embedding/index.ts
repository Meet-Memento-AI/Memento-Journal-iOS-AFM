// index.ts
//
// Edge function: sync-embedding
//
// Called by a Supabase Database Webhook on every INSERT/UPDATE to
// journal_entries. Generates a 768-dim embedding via Gemini
// gemini-embedding-001 and writes it back to the pgvector column.
//
// Deploy: supabase functions deploy sync-embedding --no-verify-jwt
//

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================
// CONFIGURATION
// ============================================================

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const GEMINI_EMBEDDING_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent';

// ============================================================
// TYPES
// ============================================================

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE';
  table: string;
  record: Record<string, unknown> | null;
  old_record: Record<string, unknown> | null;
}

interface GeminiEmbeddingResponse {
  embedding: {
    values: number[];
  };
}

// ============================================================
// MAIN HANDLER
// ============================================================

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const startTime = Date.now();

  // Service-role client (webhooks don't carry user JWTs)
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }, 500);
  }

  // ============================================================
  // AUTH GATE (spec-004 R1)
  // This function runs with the service-role key, so it MUST authenticate the
  // caller itself regardless of the gateway's --no-verify-jwt setting. Two paths:
  //   * DB webhook  -> shared secret header `X-Webhook-Secret` == SYNC_EMBEDDING_SECRET
  //   * iOS direct  -> a valid user JWT in `Authorization` (the app sends one)
  // If a secret is configured we accept either; without it we require a user JWT.
  // ============================================================
  const webhookSecret = Deno.env.get('SYNC_EMBEDDING_SECRET');
  const providedSecret = req.headers.get('x-webhook-secret');
  const authHeader = req.headers.get('Authorization');
  let authorized = false;

  if (webhookSecret && providedSecret && providedSecret === webhookSecret) {
    authorized = true; // trusted webhook
  } else if (authHeader) {
    // Verify the user JWT with an anon client scoped to this request.
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    authorized = !userErr && !!user;
  }

  if (!authorized) {
    return jsonResponse({ error: 'Unauthorized', code: 'AUTH_ERROR' }, 401);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  let recordId: string | undefined;

  try {
    const body = await req.json();

    // ============================================================
    // Support direct invocation with entryId (from iOS app)
    // ============================================================
    let payload: WebhookPayload;

    if (body.entryId && !body.type) {
      // Direct invocation from client - fetch the entry
      const { data: entry, error: fetchError } = await supabase
        .from('journal_entries')
        .select('id, content, embedding_status, embedding')
        .eq('id', body.entryId)
        .single();

      if (fetchError || !entry) {
        console.warn(`⚠️ Entry not found: ${body.entryId}`);
        return jsonResponse({ error: 'Entry not found', id: body.entryId }, 404);
      }

      // Create a synthetic payload to continue with existing logic
      payload = {
        type: 'UPDATE',
        table: 'journal_entries',
        record: entry,
        old_record: null
      };

      console.log(`📲 Direct invocation for entry ${body.entryId}`);
    } else {
      // Standard webhook payload
      payload = body as WebhookPayload;
    }

    // Nothing to embed for deletes — row is gone
    if (payload.type === 'DELETE') {
      return jsonResponse({ success: true, status: 'skipped_delete' }, 200);
    }

    const record = payload.record;
    if (!record) {
      return jsonResponse({ error: 'No record in payload' }, 400);
    }

    recordId = record.id as string;
    const content = record.content as string | null;

    if (!content || content.trim().length === 0) {
      await supabase
        .from('journal_entries')
        .update({ embedding_status: 'failed' })
        .eq('id', recordId);

      console.warn(`⚠️ Empty content for entry ${recordId}, marked as failed`);
      return jsonResponse({ success: true, id: recordId, status: 'failed_empty' }, 200);
    }

    // Skip if already embedded and content hasn't changed
    if (record.embedding_status === 'complete' && record.embedding !== null) {
      return jsonResponse({ success: true, id: recordId, status: 'already_complete' }, 200);
    }

    // ============================================================
    // Generate embedding via Gemini gemini-embedding-001
    // ============================================================

    const geminiApiKey = Deno.env.get('GEMINI_API_KEY');
    if (!geminiApiKey) {
      throw new Error('GEMINI_API_KEY not configured');
    }

    const embeddingResponse = await fetch(
      `${GEMINI_EMBEDDING_URL}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': geminiApiKey },
        body: JSON.stringify({
          model: 'models/gemini-embedding-001',
          content: { parts: [{ text: content }] },
          outputDimensionality: 768,
        }),
      }
    );

    if (!embeddingResponse.ok) {
      const errText = await embeddingResponse.text();
      throw new Error(`Gemini API error ${embeddingResponse.status}: ${errText}`);
    }

    const embeddingData: GeminiEmbeddingResponse = await embeddingResponse.json();
    let values = embeddingData.embedding?.values;

    if (!values || values.length < 768) {
      throw new Error(`Unexpected embedding dimensions: ${values?.length ?? 0}`);
    }

    // Use first 768 dimensions if outputDimensionality was ignored (e.g., 3072 from gemini-embedding-001)
    if (values.length !== 768) {
      values = values.slice(0, 768);
    }

    // Format as pgvector literal
    const vectorLiteral = `[${values.join(',')}]`;

    // ============================================================
    // Write embedding back to journal_entries
    // ============================================================

    const { error: updateError } = await supabase
      .from('journal_entries')
      .update({
        embedding: vectorLiteral,
        embedding_status: 'complete',
      })
      .eq('id', recordId);

    if (updateError) {
      throw new Error(`Supabase update error: ${updateError.message}`);
    }

    const elapsed = Date.now() - startTime;
    console.log(`✅ Embedded entry ${recordId} in ${elapsed}ms`);

    return jsonResponse({ success: true, id: recordId, status: 'complete' }, 200);

  } catch (error) {
    const elapsed = Date.now() - startTime;
    console.error(`❌ Embedding failed for ${recordId ?? 'unknown'} after ${elapsed}ms:`, error);

    // Mark as failed so a future retry can pick it up
    if (recordId) {
      try {
        await supabase
          .from('journal_entries')
          .update({ embedding_status: 'failed' })
          .eq('id', recordId);
      } catch (markError) {
        console.error('Failed to mark entry as failed:', markError);
      }
    }

    return jsonResponse(
      { error: 'Embedding generation failed', id: recordId ?? null },
      200 // Return 200 so the webhook doesn't retry endlessly
    );
  }
});

// ============================================================
// HELPERS
// ============================================================

function jsonResponse(data: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
