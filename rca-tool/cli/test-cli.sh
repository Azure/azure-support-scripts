#!/bin/bash
#
# Test script to run the CLI tool against all fixtures
#
# Usage:
#   ./test-cli.sh          # Run all tests
#   ./test-cli.sh --quick  # Run quick subset of tests
#

# Don't use set -e as arithmetic operations can return non-zero

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/dist/rca-cli.cjs"
FIXTURES_DIR="$SCRIPT_DIR/../tests/fixtures"
OUTPUT_DIR="$SCRIPT_DIR/test-output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Quick mode - only test a subset
QUICK_MODE=false
if [[ "$1" == "--quick" || "$1" == "-q" ]]; then
    QUICK_MODE=true
fi

# Quick test fixtures (representative subset)
QUICK_FIXTURES=(
    "scc_test-azure-vm.tar.xz"
    "scc_test-huge-pages.tar.xz"
    "scc_test-kernel-tuning.tar.xz"
    "scc_test-cluster-nodes.tar.xz"
    "scc_test-fstab.tar.xz"
    "scc_test-lvm.tar.xz"
    "scc_test-antivirus.tar.xz"
    "sosreport-rpm-raw.tar.xz"
)

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "  RCA CLI Test Runner"
echo "========================================"
echo ""

# Check if CLI exists
if [ ! -f "$CLI" ]; then
    echo -e "${RED}Error: CLI not found at $CLI${NC}"
    echo "Run 'npm run build' first to create the bundle"
    exit 1
fi

# Check if fixtures exist
if [ ! -d "$FIXTURES_DIR" ]; then
    echo -e "${RED}Error: Fixtures directory not found at $FIXTURES_DIR${NC}"
    exit 1
fi

# Count fixtures
if [ "$QUICK_MODE" = true ]; then
    TOTAL=${#QUICK_FIXTURES[@]}
    echo "Running quick test with $TOTAL fixtures"
else
    TOTAL=$(find "$FIXTURES_DIR" -maxdepth 1 -name "*.tar.xz" | wc -l)
    echo "Found $TOTAL fixture files"
fi
echo ""

# Function to test a single fixture
test_fixture() {
    local fixture="$1"
    local filename=$(basename "$fixture")
    local testname="${filename%.tar.xz}"
    
    # Skip corrupted test (expected to fail)
    if [[ "$filename" == *"corrupted"* ]]; then
        echo -e "${YELLOW}SKIP${NC} $filename (expected failure test)"
        ((SKIPPED++))
        return
    fi
    
    echo -n "Testing: $filename ... "
    
    # Run CLI and capture output
    local output_file="$OUTPUT_DIR/${testname}.txt"
    local json_file="$OUTPUT_DIR/${testname}.json"
    
    # Run with text output
    if "$CLI" "$fixture" > "$output_file" 2>&1; then
        # Check that output is not empty and contains expected sections
        if grep -q "RCA Analysis Results" "$output_file"; then
            echo -e "${GREEN}PASS${NC}"
            ((PASSED++))
        else
            echo -e "${RED}FAIL${NC} (no results in output)"
            ((FAILED++))
        fi
    else
        echo -e "${RED}FAIL${NC} (exit code $?)"
        ((FAILED++))
    fi
}

# Run tests
if [ "$QUICK_MODE" = true ]; then
    for filename in "${QUICK_FIXTURES[@]}"; do
        fixture="$FIXTURES_DIR/$filename"
        if [ -f "$fixture" ]; then
            test_fixture "$fixture"
        else
            echo -e "${YELLOW}SKIP${NC} $filename (not found)"
            ((SKIPPED++))
        fi
    done
else
    for fixture in "$FIXTURES_DIR"/*.tar.xz; do
        test_fixture "$fixture"
    done
fi

echo ""
echo "========================================"
echo "  Results"
echo "========================================"
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo "  Total:   $TOTAL"
echo ""
echo "Output files saved to: $OUTPUT_DIR"
echo ""

# Exit with failure if any tests failed
if [ $FAILED -gt 0 ]; then
    exit 1
fi

exit 0
