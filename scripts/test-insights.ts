#!/usr/bin/env -S deno run --allow-net --allow-env --allow-read

/**
 * Test script for generate-insights edge function
 *
 * Usage:
 *   1. Start edge function: supabase functions serve generate-insights
 *   2. Run this script: deno run --allow-net --allow-env --allow-read test-insights.ts
 *
 * Or use production:
 *   Set USE_PRODUCTION=true in script below
 */

import { load } from "https://deno.land/std@0.168.0/dotenv/mod.ts";

// Load environment variables from .env
const env = await load();

// Configuration
const USE_PRODUCTION = true;  // Set to true to test production endpoint
const LOCAL_URL = 'http://localhost:54321/functions/v1/generate-insights';
const PRODUCTION_URL = 'https://fhsgvlbedqwxwpubtlls.supabase.co/functions/v1/generate-insights';

const ENDPOINT_URL = USE_PRODUCTION ? PRODUCTION_URL : LOCAL_URL;
const ANON_KEY = env.SUPABASE_ANON_KEY || Deno.env.get('SUPABASE_ANON_KEY');
const USER_TOKEN = env.USER_ACCESS_TOKEN || Deno.env.get('USER_ACCESS_TOKEN');

if (!ANON_KEY) {
  console.error('❌ Error: SUPABASE_ANON_KEY not found in .env or environment');
  Deno.exit(1);
}

if (!USER_TOKEN) {
  console.error('❌ Error: USER_ACCESS_TOKEN not found in .env');
  console.error('   Run ./get-user-token.ts to get your user token');
  Deno.exit(1);
}

// ANSI color codes for pretty output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  gray: '\x1b[90m',
};

// Test scenarios
const testScenarios = [
  {
    name: "3 Entries - Minimum for Insights",
    forceRefresh: false,
    entries: [
      {
        date: "2025-01-15T10:00:00Z",
        title: "Morning Anxiety",
        content: "Woke up feeling anxious about the presentation today. Can't shake this feeling of dread. Keep replaying worst-case scenarios in my head.",
        word_count: 22,
        mood: "anxious"
      },
      {
        date: "2025-01-16T14:30:00Z",
        title: "Presentation Relief",
        content: "The presentation went better than expected! Everyone seemed engaged and I got positive feedback. Still can't believe I pulled it off.",
        word_count: 24,
        mood: "relieved"
      },
      {
        date: "2025-01-17T09:00:00Z",
        title: "Weekend Reset",
        content: "Planning a solo hike this weekend. Nature always helps me process emotions and gain perspective. Looking forward to some quiet time.",
        word_count: 23,
        mood: "hopeful"
      }
    ]
  },
  {
    name: "6 Entries - Milestone Test",
    forceRefresh: true,
    entries: [
      {
        date: "2025-01-15T10:00:00Z",
        title: "Work Stress Building",
        content: "Deadlines are piling up. Feeling overwhelmed by the amount of work on my plate.",
        word_count: 15,
        mood: "stressed"
      },
      {
        date: "2025-01-16T14:30:00Z",
        title: "Team Conflict",
        content: "Had a disagreement with a colleague today. Feeling frustrated about communication issues.",
        word_count: 13,
        mood: "frustrated"
      },
      {
        date: "2025-01-17T09:00:00Z",
        title: "Self-Care Sunday",
        content: "Took time for myself today. Yoga and meditation helped me feel more centered.",
        word_count: 14,
        mood: "calm"
      },
      {
        date: "2025-01-18T20:00:00Z",
        title: "Family Dinner",
        content: "Nice evening with family. Reminded me of what really matters in life.",
        word_count: 13,
        mood: "grateful"
      },
      {
        date: "2025-01-19T11:00:00Z",
        title: "Creative Breakthrough",
        content: "Finally figured out that problem I've been stuck on. Feeling energized and motivated.",
        word_count: 14,
        mood: "excited"
      },
      {
        date: "2025-01-20T16:00:00Z",
        title: "Reflection Time",
        content: "Looking back at the week. Growth isn't linear but I'm making progress.",
        word_count: 13,
        mood: "reflective"
      }
    ]
  },
  {
    name: "Force Refresh Test",
    forceRefresh: true,
    entries: [
      {
        date: "2025-01-21T10:00:00Z",
        title: "New Chapter",
        content: "Starting something new today. Nervous but excited about this change.",
        word_count: 11,
        mood: "hopeful"
      },
      {
        date: "2025-01-22T14:00:00Z",
        title: "Day Two Progress",
        content: "Second day went smoother. Building confidence with each step forward.",
        word_count: 11,
        mood: "confident"
      },
      {
        date: "2025-01-23T09:00:00Z",
        title: "Finding My Rhythm",
        content: "Starting to find my rhythm. This feels right and I'm proud of myself.",
        word_count: 14,
        mood: "proud"
      }
    ]
  }
];

// Helper function to call edge function
async function testInsights(scenario: any) {
  const startTime = Date.now();

  console.log(`\n${colors.bright}${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`);
  console.log(`${colors.bright}Test: ${scenario.name}${colors.reset}`);
  console.log(`${colors.gray}Entries: ${scenario.entries.length} | Force Refresh: ${scenario.forceRefresh}${colors.reset}`);
  console.log(`${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}\n`);

  const requestBody = {
    entries: scenario.entries,
    force_refresh: scenario.forceRefresh
  };

  try {
    const response = await fetch(ENDPOINT_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${USER_TOKEN}`,  // Use user token for authentication
        'apikey': ANON_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody)
    });

    const responseTime = Date.now() - startTime;
    const data = await response.json();

    if (response.ok) {
      console.log(`${colors.green}✅ Success (${responseTime}ms)${colors.reset}\n`);

      // Print summary
      console.log(`${colors.bright}Summary:${colors.reset} ${data.summary}`);
      console.log(`\n${colors.bright}Description:${colors.reset}\n${data.description}`);
      console.log(`\n${colors.bright}Themes (${data.themes.length}):${colors.reset}`);

      data.themes.forEach((theme: any, index: number) => {
        console.log(`\n  ${colors.yellow}${index + 1}. ${theme.icon} ${theme.name}${colors.reset}`);
        console.log(`     ${colors.gray}${theme.explanation}${colors.reset}`);
        console.log(`     ${colors.gray}Frequency: ${theme.frequency}${colors.reset}`);
        console.log(`     ${colors.gray}Sources: ${theme.source_entries.length} entries${colors.reset}`);
      });

      console.log(`\n${colors.bright}Metadata:${colors.reset}`);
      console.log(`  Entries Analyzed: ${data.entriesAnalyzed}`);
      console.log(`  Generated At: ${new Date(data.generatedAt).toLocaleString()}`);
      console.log(`  From Cache: ${data.fromCache ? '✓' : '✗'}`);
      if (data.cacheExpiresAt) {
        console.log(`  Cache Expires: ${new Date(data.cacheExpiresAt).toLocaleString()}`);
      }

      return { success: true, responseTime };
    } else {
      console.log(`${colors.red}❌ Failed (${response.status})${colors.reset}\n`);
      console.log(`${colors.red}Error:${colors.reset} ${data.error || 'Unknown error'}`);
      if (data.code) {
        console.log(`${colors.red}Code:${colors.reset} ${data.code}`);
      }

      return { success: false, responseTime, error: data };
    }
  } catch (error) {
    const responseTime = Date.now() - startTime;
    console.log(`${colors.red}❌ Network Error (${responseTime}ms)${colors.reset}\n`);
    console.log(`${colors.red}${error}${colors.reset}`);

    return { success: false, responseTime, error };
  }
}

// Main test runner
async function runTests() {
  console.log(`\n${colors.bright}${colors.blue}╔════════════════════════════════════════════════════╗${colors.reset}`);
  console.log(`${colors.bright}${colors.blue}║  Generate Insights Edge Function Test Suite       ║${colors.reset}`);
  console.log(`${colors.bright}${colors.blue}╚════════════════════════════════════════════════════╝${colors.reset}`);
  console.log(`\n${colors.gray}Endpoint: ${USE_PRODUCTION ? 'PRODUCTION' : 'LOCAL'}${colors.reset}`);
  console.log(`${colors.gray}URL: ${ENDPOINT_URL}${colors.reset}`);

  const results = [];

  for (const scenario of testScenarios) {
    const result = await testInsights(scenario);
    results.push({ name: scenario.name, ...result });
  }

  // Summary
  console.log(`\n${colors.bright}${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}`);
  console.log(`${colors.bright}Test Summary${colors.reset}`);
  console.log(`${colors.cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}\n`);

  const passed = results.filter(r => r.success).length;
  const failed = results.filter(r => !r.success).length;
  const avgTime = Math.round(results.reduce((sum, r) => sum + r.responseTime, 0) / results.length);

  results.forEach(result => {
    const status = result.success
      ? `${colors.green}✓ PASS${colors.reset}`
      : `${colors.red}✗ FAIL${colors.reset}`;
    console.log(`  ${status} ${result.name} (${result.responseTime}ms)`);
  });

  console.log(`\n${colors.bright}Results:${colors.reset}`);
  console.log(`  ${colors.green}Passed: ${passed}${colors.reset}`);
  console.log(`  ${colors.red}Failed: ${failed}${colors.reset}`);
  console.log(`  ${colors.gray}Average Response Time: ${avgTime}ms${colors.reset}\n`);

  if (failed > 0) {
    Deno.exit(1);
  }
}

// Run the tests
await runTests();
