#!/bin/bash
#
# verify_preview_optimization.sh
# Checks that all previews follow optimization best practices
#

echo "🔍 Verifying SwiftUI Preview Optimizations..."
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Counters
total_previews=0
optimized_previews=0
unoptimized_previews=0

# Check 1: Find all preview declarations
echo "📊 Checking preview files..."
preview_files=$(find . -name "*.swift" -type f -not -path "*/DerivedData/*" -not -path "*/.build/*" | xargs grep -l "#Preview\|PreviewProvider")

if [ -z "$preview_files" ]; then
    echo "${RED}❌ No preview files found${NC}"
    exit 1
fi

# Check 2: Verify .previewLayout usage
echo ""
echo "⚡️ Checking for .previewLayout(.sizeThatFits)..."
echo ""

while IFS= read -r file; do
    # Count previews in file
    preview_count=$(grep -c "#Preview\|PreviewProvider" "$file" 2>/dev/null || echo 0)
    
    if [ "$preview_count" -gt 0 ]; then
        total_previews=$((total_previews + preview_count))
        
        # Check if file uses .previewLayout
        if grep -q "\.previewLayout(.sizeThatFits)" "$file" 2>/dev/null; then
            echo "${GREEN}✅ $file${NC}"
            optimized_previews=$((optimized_previews + 1))
        else
            echo "${YELLOW}⚠️  $file - Missing .previewLayout(.sizeThatFits)${NC}"
            unoptimized_previews=$((unoptimized_previews + 1))
        fi
    fi
done <<< "$preview_files"

# Check 3: Look for anti-patterns
echo ""
echo "🚨 Checking for preview anti-patterns..."
echo ""

anti_patterns_found=0

# Anti-pattern 1: Complex environment setup in previews
echo "Checking for .useTheme().useTypography() in single line..."
if grep -r "\.useTheme()\.useTypography()" --include="*.swift" . 2>/dev/null | grep -v "Binary" | grep "#Preview" > /dev/null; then
    echo "${YELLOW}⚠️  Found chained .useTheme().useTypography() - consider simplifying${NC}"
    anti_patterns_found=$((anti_patterns_found + 1))
fi

# Anti-pattern 2: Complex nested views in previews
echo "Checking for deeply nested preview hierarchies..."
if grep -rA 5 "#Preview" --include="*.swift" . 2>/dev/null | grep -c "NavigationStack.*VStack.*HStack" > /dev/null; then
    echo "${YELLOW}⚠️  Found complex nested hierarchies in previews${NC}"
    anti_patterns_found=$((anti_patterns_found + 1))
fi

# Anti-pattern 3: Missing light/dark split
echo "Checking for separate light/dark previews..."
files_with_dark=$(grep -rl "#Preview.*Dark\|preferredColorScheme(.dark)" --include="*.swift" . 2>/dev/null | wc -l)
files_with_light=$(grep -rl "#Preview.*Light" --include="*.swift" . 2>/dev/null | wc -l)

if [ "$files_with_dark" -lt "$files_with_light" ]; then
    echo "${YELLOW}⚠️  Some files missing dark mode previews${NC}"
    anti_patterns_found=$((anti_patterns_found + 1))
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total preview files: $total_previews"
echo "${GREEN}Optimized: $optimized_previews${NC}"
echo "${YELLOW}Needs optimization: $unoptimized_previews${NC}"
echo "${RED}Anti-patterns found: $anti_patterns_found${NC}"
echo ""

# Calculate percentage
if [ "$total_previews" -gt 0 ]; then
    percentage=$((optimized_previews * 100 / total_previews))
    echo "Optimization coverage: ${percentage}%"
    
    if [ "$percentage" -ge 90 ]; then
        echo "${GREEN}🎉 Excellent! Your previews are well optimized!${NC}"
        exit 0
    elif [ "$percentage" -ge 70 ]; then
        echo "${YELLOW}⚠️  Good progress! A few more files need optimization.${NC}"
        exit 0
    else
        echo "${RED}❌ Many previews need optimization. See PREVIEW_OPTIMIZATION_GUIDE.md${NC}"
        exit 1
    fi
else
    echo "${RED}❌ No previews found to verify${NC}"
    exit 1
fi

