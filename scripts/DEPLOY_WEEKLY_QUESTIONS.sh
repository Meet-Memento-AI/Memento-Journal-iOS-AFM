#!/bin/bash
# Deployment Script for Continuous Weekly Question Generation
# Option 2: Scheduled Weekly Generation

set -e  # Exit on any error

echo "🚀 Deploying Continuous Weekly Question Generation System"
echo "=========================================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "supabase/config.toml" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    echo "Current directory: $(pwd)"
    echo "Expected: /Users/sebastianmendo/Swift-projects/MeetMemento"
    exit 1
fi

echo -e "${BLUE}Step 1/5: Checking Prerequisites${NC}"
echo "-----------------------------------"

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI not found${NC}"
    echo "Install with: brew install supabase/tap/supabase"
    exit 1
fi
echo -e "${GREEN}✓ Supabase CLI installed${NC}"

# Check if logged in
if ! supabase projects list &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not logged in to Supabase${NC}"
    echo "Running: supabase login"
    supabase login
fi
echo -e "${GREEN}✓ Logged in to Supabase${NC}"

# Check if project is linked
if [ ! -f ".supabase/config.toml" ]; then
    echo -e "${YELLOW}⚠️  Project not linked${NC}"
    echo "Please link your project:"
    echo "  supabase link --project-ref YOUR_PROJECT_REF"
    echo ""
    echo "Find your project ref at:"
    echo "  https://supabase.com/dashboard → Your Project → Settings → General → Reference ID"
    exit 1
fi
echo -e "${GREEN}✓ Project linked${NC}"
echo ""

echo -e "${BLUE}Step 2/5: Running Database Migration${NC}"
echo "---------------------------------------"
echo "This creates the follow_up_questions table..."
supabase db push
echo -e "${GREEN}✓ Migration complete${NC}"
echo ""

echo -e "${BLUE}Step 3/5: Deploying generate-follow-up Function${NC}"
echo "--------------------------------------------------"
echo "This deploys the TF-IDF question generation function..."
supabase functions deploy generate-follow-up
echo -e "${GREEN}✓ Function deployed${NC}"
echo ""

echo -e "${BLUE}Step 4/5: Deploying weekly-question-generator Cron${NC}"
echo "----------------------------------------------------"
echo "This deploys the weekly automatic generation function..."
supabase functions deploy weekly-question-generator
echo -e "${GREEN}✓ Cron function deployed${NC}"
echo ""

echo -e "${BLUE}Step 5/5: Manual Testing${NC}"
echo "------------------------"
echo ""
echo -e "${YELLOW}⚠️  Next steps (manual):${NC}"
echo ""
echo "1. Get your JWT token:"
echo "   - Sign in to your app in Xcode"
echo "   - Add breakpoint after auth"
echo "   - Print: supabase.auth.session?.accessToken"
echo ""
echo "2. Test question generation:"
echo "   export JWT_TOKEN=\"your_token_here\""
echo "   bash TEST_QUESTIONS.sh"
echo ""
echo "3. Set up weekly cron schedule:"
echo "   - Go to: https://supabase.com/dashboard"
echo "   - Navigate to: Edge Functions → weekly-question-generator"
echo "   - Click: Settings tab"
echo "   - Enable Cron: 0 21 * * 0 (Every Sunday 9 PM UTC)"
echo "   - Click: Save"
echo ""
echo "4. (Optional) Set cron secret for security:"
echo "   - In same page: Secrets tab"
echo "   - Add secret: CRON_SECRET = (random string)"
echo "   - Generate with: openssl rand -hex 32"
echo ""
echo -e "${GREEN}=========================================================="
echo "🎉 Deployment Complete!"
echo "==========================================================${NC}"
echo ""
echo "Check deployment guide for Swift integration:"
echo "  CONTINUOUS_QUESTIONS_IMPLEMENTATION.md"
echo ""
