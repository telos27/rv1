#!/bin/bash
# run_quick_regression.sh - Quick regression test suite
# Runs 15 essential tests in ~20-30 seconds for rapid feedback

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

XLEN=${XLEN:-32}

echo ""
echo "═══════════════════════════════════════"
echo "  RV1 Quick Regression Suite"
echo "═══════════════════════════════════════"
echo ""

passed=0
failed=0

# Helper function
run_test() {
    local name=$1
    local cmd=$2
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $name"
        ((passed++))
    else
        echo -e "  ${RED}✗${NC} $name"
        ((failed++))
    fi
}

start=$(date +%s)

# RV32I - Base (2 tests)
run_test "rv32ui-p-add" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh i add 2>&1 | grep -q PASSED"
run_test "rv32ui-p-jal" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh i jal 2>&1 | grep -q PASSED"

# RV32M - Multiply/Divide (2 tests)
run_test "rv32um-p-mul" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh m mul 2>&1 | grep -q PASSED"
run_test "rv32um-p-div" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh m div 2>&1 | grep -q PASSED"

# RV32A - Atomics (2 tests)
run_test "rv32ua-p-amoswap_w" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh a amoswap_w 2>&1 | grep -q PASSED"
run_test "rv32ua-p-lrsc" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh a lrsc 2>&1 | grep -q PASSED"

# RV32F - Single FP (2 tests)
run_test "rv32uf-p-fadd" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh f fadd 2>&1 | grep -q PASSED"
run_test "rv32uf-p-fcvt" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh f fcvt 2>&1 | grep -q PASSED"

# RV32D - Double FP (2 tests)
run_test "rv32ud-p-fadd" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh d fadd 2>&1 | grep -q PASSED"
run_test "rv32ud-p-fcvt" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh d fcvt 2>&1 | grep -q PASSED"

# RV32C - Compressed (1 test)
run_test "rv32uc-p-rvc" "timeout 5s env XLEN=32 ./tools/run_official_tests.sh c rvc 2>&1 | grep -q PASSED"

# Custom tests (3 fast tests)
run_test "test_fp_compare_simple" "timeout 5s env XLEN=32 ./tools/test_pipelined.sh test_fp_compare_simple"
run_test "test_priv_minimal" "timeout 5s env XLEN=32 ./tools/test_pipelined.sh test_priv_minimal"
run_test "test_fp_add_simple" "timeout 5s env XLEN=32 ./tools/test_pipelined.sh test_fp_add_simple"

end=$(date +%s)
elapsed=$((end - start))
total=$((passed + failed))

echo ""
echo "═══════════════════════════════════════"
echo "  Quick Regression Summary"
echo "═══════════════════════════════════════"
echo ""
echo "Total:   $total tests"
echo -e "Passed:  ${GREEN}$passed${NC}"
echo -e "Failed:  ${RED}$failed${NC}"
echo "Time:    ${elapsed}s"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ All quick regression tests PASSED!${NC}"
    echo ""
    echo "Safe to proceed with development."
    exit 0
else
    echo -e "${RED}✗ Some tests FAILED${NC}"
    echo ""
    echo "Run full test suite:"
    echo "  env XLEN=32 ./tools/run_official_tests.sh all"
    exit 1
fi
