// index.ts
//
// Edge function: chat-feedback
//
// Endpoint for submitting thumbs up/down feedback on AI chat responses.
// Allows toggling feedback: submitting the same type clears it.
//
// Deploy: supabase functions deploy chat-feedback
//

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { requireAuth } from '../_shared/auth.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, DELETE, OPTIONS',
};

interface FeedbackRequest {
  messageId: string;
  feedbackType: 'positive' | 'negative';
}

interface FeedbackResponse {
  success: boolean;
  feedbackType: string | null;
  action: 'created' | 'updated' | 'deleted';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 1. Authenticate user
    const auth = await requireAuth(req, corsHeaders);
    if (auth instanceof Response) return auth;
    const { user, supabase } = auth;

    // 2. Parse request
    if (req.method !== 'POST' && req.method !== 'DELETE') {
      return jsonResponse({ error: 'Method not allowed' }, 405);
    }

    let body: FeedbackRequest;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: 'Invalid JSON body' }, 400);
    }

    const { messageId, feedbackType } = body;

    if (!messageId) {
      return jsonResponse({ error: 'messageId is required' }, 400);
    }

    if (feedbackType && !['positive', 'negative'].includes(feedbackType)) {
      return jsonResponse({ error: 'feedbackType must be "positive" or "negative"' }, 400);
    }

    // 3. Validate message belongs to user
    const { data: message, error: messageError } = await supabase
      .from('chat_messages')
      .select('id, user_id, role')
      .eq('id', messageId)
      .single();

    if (messageError || !message) {
      console.error('Message lookup error:', messageError);
      return jsonResponse({ error: 'Message not found' }, 404);
    }

    if (message.user_id !== user.id) {
      return jsonResponse({ error: 'Unauthorized to provide feedback on this message' }, 403);
    }

    // Only allow feedback on assistant messages
    if (message.role !== 'assistant') {
      return jsonResponse({ error: 'Can only provide feedback on AI responses' }, 400);
    }

    // 4. Check existing feedback
    const { data: existingFeedback } = await supabase
      .from('chat_feedback')
      .select('id, feedback_type')
      .eq('user_id', user.id)
      .eq('message_id', messageId)
      .single();

    // 5. Handle DELETE request or toggle behavior
    if (req.method === 'DELETE' || existingFeedback?.feedback_type === feedbackType) {
      // Delete existing feedback (toggle off)
      if (existingFeedback) {
        const { error: deleteError } = await supabase
          .from('chat_feedback')
          .delete()
          .eq('id', existingFeedback.id);

        if (deleteError) {
          console.error('Delete feedback error:', deleteError);
          return jsonResponse({ error: 'Failed to delete feedback' }, 500);
        }

        console.log(`🗑️ Deleted feedback for message ${messageId.substring(0, 8)}`);
        return jsonResponse({
          success: true,
          feedbackType: null,
          action: 'deleted'
        } as FeedbackResponse, 200);
      }

      // No existing feedback to delete
      return jsonResponse({
        success: true,
        feedbackType: null,
        action: 'deleted'
      } as FeedbackResponse, 200);
    }

    // 6. Upsert feedback (create or update)
    if (existingFeedback) {
      // Update existing feedback to new type
      const { error: updateError } = await supabase
        .from('chat_feedback')
        .update({ feedback_type: feedbackType })
        .eq('id', existingFeedback.id);

      if (updateError) {
        console.error('Update feedback error:', updateError);
        return jsonResponse({ error: 'Failed to update feedback' }, 500);
      }

      console.log(`✏️ Updated feedback to ${feedbackType} for message ${messageId.substring(0, 8)}`);
      return jsonResponse({
        success: true,
        feedbackType,
        action: 'updated'
      } as FeedbackResponse, 200);
    } else {
      // Create new feedback
      const { error: insertError } = await supabase
        .from('chat_feedback')
        .insert({
          user_id: user.id,
          message_id: messageId,
          feedback_type: feedbackType,
        });

      if (insertError) {
        console.error('Insert feedback error:', insertError);
        return jsonResponse({ error: 'Failed to save feedback' }, 500);
      }

      console.log(`👍 Created ${feedbackType} feedback for message ${messageId.substring(0, 8)}`);
      return jsonResponse({
        success: true,
        feedbackType,
        action: 'created'
      } as FeedbackResponse, 200);
    }

  } catch (error) {
    console.error('❌ Chat feedback error:', error);
    return jsonResponse({ error: 'Internal server error' }, 500);
  }
});

function jsonResponse(data: FeedbackResponse | { error: string }, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
