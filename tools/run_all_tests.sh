#!/bin/bash
# run_all_tests.sh - Run all test programs

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
TOTAL=0

echo "======================================"
echo "  RV1 RISC-V Processor Test Suite"
echo "======================================"
echo ""

# Find all hex files in tests/vectors
HEX_FILES=$(find tests/vectors -name "*.hex" 2>/dev/null | sort)

if [ -z "$HEX_FILES" ]; then
    echo "No test files found in tests/vectors/"
    echo "Run 'make asm-tests' to build test programs"
    exit 1
fi

# Run each test
for HEX_FILE in $HEX_FILES; do
    TEST_NAME=$(basename "$HEX_FILE" .hex)
    TOTAL=$((TOTAL + 1))

    echo -n "[$TOTAL] Testing $TEST_NAME... "

    if ./tools/run_test.sh "$TEST_NAME" 10000 > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))

        # Show failure details
        if [ -f "sim/${TEST_NAME}.log" ]; then
            echo "  Last 10 lines of log:"
            tail -10 "sim/${TEST_NAME}.log" | sed 's/^/    /'
        fi
    fi
done

# Summary
echo ""
echo "======================================"
echo "  Test Summary"
echo "======================================"
echo "Total:  $TOTAL"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
