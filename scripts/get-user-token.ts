#!/usr/bin/env -S deno run --allow-net --allow-env --allow-read

/**
 * Get a user authentication token for testing edge functions
 *
 * Usage:
 *   1. Run: ./get-user-token.ts
 *   2. Enter your email and password
 *   3. Copy the access_token
 *   4. Add it to .env as USER_ACCESS_TOKEN
 */

import { load } from "https://deno.land/std@0.168.0/dotenv/mod.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const env = await load();
const SUPABASE_URL = env.SUPABASE_URL || 'https://fhsgvlbedqwxwpubtlls.supabase.co';
const SUPABASE_ANON_KEY = env.SUPABASE_ANON_KEY;

if (!SUPABASE_ANON_KEY) {
  console.error('❌ SUPABASE_ANON_KEY not found in .env');
  Deno.exit(1);
}

// Prompt for credentials
console.log('\n🔐 Login to get user access token\n');
const email = prompt('Email:');
const password = prompt('Password:', { default: '' });

if (!email || !password) {
  console.error('❌ Email and password required');
  Deno.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

console.log('\n🔄 Logging in...\n');

const { data, error } = await supabase.auth.signInWithPassword({
  email: email,
  password: password,
});

if (error) {
  console.error('❌ Login failed:', error.message);
  Deno.exit(1);
}

if (data.session) {
  console.log('✅ Login successful!\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('User ID:', data.user.id);
  console.log('Email:', data.user.email);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  console.log('📋 Copy this access token:\n');
  console.log(data.session.access_token);
  console.log('\n');

  console.log('💡 Add it to your .env file:');
  console.log('USER_ACCESS_TOKEN=' + data.session.access_token);
  console.log('\n');

  console.log('⏰ Token expires at:', new Date(data.session.expires_at! * 1000).toLocaleString());
  console.log('   (Valid for ~1 hour)\n');
} else {
  console.error('❌ No session returned');
  Deno.exit(1);
}
