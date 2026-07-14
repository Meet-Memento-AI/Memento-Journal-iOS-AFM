#!/bin/bash
# Testing Script for Continuous Weekly Question Generation
# Run this after deployment to verify everything works

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🧪 Testing Weekly Question Generation System"
echo "=============================================="
echo ""

# Check if JWT_TOKEN is set
if [ -z "$JWT_TOKEN" ]; then
    echo -e "${RED}❌ Error: JWT_TOKEN not set${NC}"
    echo ""
    echo "How to get your JWT token:"
    echo "1. Open your app in Xcode"
    echo "2. Sign in with your test account"
    echo "3. Add this line after authentication:"
    echo '   print("JWT:", supabase.auth.session?.accessToken ?? "none")'
    echo "4. Copy the token from console"
    echo ""
    echo "Then set it:"
    echo '  export JWT_TOKEN="your_token_here"'
    echo ""
    exit 1
fi

# Get project URL from config
if [ -f ".supabase/config.toml" ]; then
    PROJECT_URL=$(grep -A 1 "\[api\]" .supabase/config.toml | grep "url" | cut -d '"' -f 2 || echo "")
fi

if [ -z "$PROJECT_URL" ]; then
    echo -e "${RED}❌ Error: Could not find Supabase project URL${NC}"
    echo "Please set manually:"
    echo '  export PROJECT_URL="https://your-project.supabase.co"'
    exit 1
fi

echo -e "${BLUE}Project URL:${NC} $PROJECT_URL"
echo -e "${BLUE}JWT Token:${NC} ${JWT_TOKEN:0:20}...${JWT_TOKEN: -10}"
echo ""

# ============================================================
# TEST 1: Generate Questions (Manual)
# ============================================================

echo -e "${BLUE}Test 1: Manual Question Generation${NC}"
echo "------------------------------------"
echo "Generating questions with 14-day lookback and database save..."
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROJECT_URL/functions/v1/generate-follow-up" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "lookbackDays": 14,
    "saveToDatabase": true
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}✓ Success! (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    echo ""

    # Extract question count
    QUESTION_COUNT=$(echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('questions', [])))" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}Generated $QUESTION_COUNT questions${NC}"
else
    echo -e "${RED}✗ Failed (HTTP $HTTP_CODE)${NC}"
    echo "Response:"
    echo "$BODY"
    exit 1
fi

echo ""

# ============================================================
# TEST 2: Verify Database Storage
# ============================================================

echo -e "${BLUE}Test 2: Verify Database Storage${NC}"
echo "----------------------------------"
echo "This requires SQL access to Supabase Dashboard"
echo ""
echo "Go to: https://supabase.com/dashboard → SQL Editor"
echo "Run this query:"
echo ""
echo -e "${YELLOW}SELECT * FROM follow_up_questions"
echo "WHERE user_id = auth.uid()"
echo "ORDER BY generated_at DESC"
echo "LIMIT 10;${NC}"
echo ""
echo "Expected: See questions just generated with today's date"
echo ""
read -p "Press Enter when verified or Ctrl+C to skip..."
echo ""

# ============================================================
# TEST 3: Test Cron Job (Manual Trigger)
# ============================================================

echo -e "${BLUE}Test 3: Test Cron Job${NC}"
echo "----------------------"
echo "Manually triggering weekly-question-generator..."
echo ""

CRON_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROJECT_URL/functions/v1/weekly-question-generator" \
  -H "Content-Type: application/json")

CRON_HTTP_CODE=$(echo "$CRON_RESPONSE" | tail -n1)
CRON_BODY=$(echo "$CRON_RESPONSE" | sed '$d')

if [ "$CRON_HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}✓ Cron job executed successfully! (HTTP $CRON_HTTP_CODE)${NC}"
    echo ""
    echo "Results:"
    echo "$CRON_BODY" | python3 -m json.tool 2>/dev/null || echo "$CRON_BODY"
else
    echo -e "${YELLOW}⚠️  Cron job response (HTTP $CRON_HTTP_CODE)${NC}"
    echo "Response:"
    echo "$CRON_BODY"
    echo ""
    echo "Note: This may fail if cron secret is enabled"
fi

echo ""

# ============================================================
# TEST 4: Check Function Logs
# ============================================================

echo -e "${BLUE}Test 4: Check Function Logs${NC}"
echo "----------------------------"
echo "Viewing recent logs from generate-follow-up function..."
echo ""

supabase functions logs generate-follow-up --limit 20 2>&1 | head -50

echo ""
echo "To view real-time logs, run:"
echo "  supabase functions logs generate-follow-up --tail"
echo ""

# ============================================================
# SUMMARY
# ============================================================

echo -e "${GREEN}=============================================="
echo "🎉 Testing Complete!"
echo "==============================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. ✅ Verify questions in database (see Test 2)"
echo ""
echo "2. 🔧 Set up automatic cron schedule:"
echo "   - Go to: https://supabase.com/dashboard"
echo "   - Edge Functions → weekly-question-generator"
echo "   - Settings → Enable Cron"
echo "   - Schedule: 0 21 * * 0 (Every Sunday 9 PM UTC)"
echo ""
echo "3. 📱 Integrate with Swift app:"
echo "   - See: CONTINUOUS_QUESTIONS_IMPLEMENTATION.md"
echo "   - Section: Phase 4 - Swift App Integration"
echo ""
echo "4. 📊 Monitor first week:"
echo "   - Check logs next Sunday evening"
echo "   - Verify questions generated for all users"
echo ""
