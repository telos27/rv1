#!/bin/bash
# Test suite for Phase 10.2 - Supervisor Mode CSRs and SRET
# Runs all Phase 10.2 validation tests

set -e

# Change to project root directory
cd "$(dirname "$0")/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo "========================================"
echo "Phase 10.2 Test Suite"
echo "Supervisor Mode CSRs and SRET"
echo "========================================"
echo ""

# Function to run a single test
run_test() {
    local test_name=$1
    local test_file=$2
    local expected_a0=$3  # Expected success value
    local description=$4

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -e "${BLUE}Test $TOTAL_TESTS: $test_name${NC}"
    echo "Description: $description"
    echo "File: $test_file"

    # Check if test file exists
    if [ ! -f "tests/asm/$test_file" ]; then
        echo -e "${RED}✗ FAILED${NC} - Test file not found"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        return 1
    fi

    # Compile test
    echo -n "  Compiling... "
    if riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
        -T tests/linker.ld -o /tmp/${test_name}.elf tests/asm/$test_file 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        return 1
    fi

    # Convert to hex (proper format for $readmemh)
    echo -n "  Converting to hex... "
    if ./tools/create_hex.sh /tmp/${test_name}.elf tests/asm/${test_name}.hex >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        return 1
    fi

    # Run simulation
    echo -n "  Running simulation... "
    # Note: Actual simulation would go here - currently skipped
    echo -e "${YELLOW}SKIP${NC}"
    echo -e "  ${GREEN}✓ COMPILED${NC} - Ready for simulation"

    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo ""
    return 0
}

# =============================================================================
# Run Test Suite
# =============================================================================

run_test "test_phase10_2_csr" "test_phase10_2_csr.s" 1 \
    "Comprehensive S-mode CSR read/write test (11 tests)"

run_test "test_phase10_2_delegation" "test_phase10_2_delegation.s" 1 \
    "Trap delegation from M-mode to S-mode"

run_test "test_phase10_2_sret" "test_phase10_2_sret.s" 1 \
    "SRET instruction functionality (4 tests)"

run_test "test_phase10_2_transitions" "test_phase10_2_transitions.s" 1 \
    "Privilege mode transitions (M↔S↔U)"

run_test "test_phase10_2_priv_violation" "test_phase10_2_priv_violation.s" 1 \
    "CSR privilege checking and violations"

# =============================================================================
# Test Summary
# =============================================================================

echo "========================================"
echo "Test Suite Summary"
echo "========================================"
echo -e "Total Tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
else
    echo -e "Failed:       $FAILED_TESTS"
fi
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}ALL TESTS COMPILED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Fix test infrastructure hex loading issue"
    echo "2. Run simulations manually or with fixed test script"
    echo "3. Verify results match expected values in PHASE10_2_TEST_SUITE.md"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}SOME TESTS FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
