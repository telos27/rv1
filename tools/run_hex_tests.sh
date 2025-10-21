#!/bin/bash
# Run compliance tests directly from hex files
# Usage: ./tools/run_hex_tests.sh [pattern]
# Example: ./tools/run_hex_tests.sh rv32uf

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RV1_DIR="$(dirname "$SCRIPT_DIR")"
HEX_DIR="$RV1_DIR/tests/official-compliance"
SIM_DIR="$RV1_DIR/sim"
RTL_DIR="$RV1_DIR/rtl"
TB_DIR="$RV1_DIR/tb"

# Check arguments
PATTERN="${1:-rv32}"
DEBUG_FPU="${DEBUG_FPU:-0}"  # Set to 1 to enable FPU debug output
DEBUG_FPU_CONVERTER="${DEBUG_FPU_CONVERTER:-0}"  # Set to 1 to enable converter debug

echo "=========================================="
echo "RV1 Compliance Tests (from hex files)"
echo "=========================================="
echo "Pattern: ${PATTERN}"
if [ "$DEBUG_FPU" = "1" ]; then
  echo "Debug: FPU debugging enabled"
fi
if [ "$DEBUG_FPU_CONVERTER" = "1" ]; then
  echo "Debug: FPU Converter debugging enabled"
fi
echo ""

# Find tests - handle both patterns:
# 1. If pattern already includes full test name (e.g. rv32uf-p-fadd), match exactly
# 2. Otherwise match all tests with that prefix (e.g. rv32uf matches rv32uf-*.hex)
if [ -f "$HEX_DIR/${PATTERN}.hex" ]; then
  # Exact match - single test
  TESTS="$HEX_DIR/${PATTERN}.hex"
else
  # Pattern match - multiple tests
  TESTS=$(ls "$HEX_DIR/${PATTERN}"*-*.hex 2>/dev/null | sort)
fi

if [ -z "$TESTS" ]; then
  echo -e "${RED}No tests found matching: ${PATTERN}${NC}"
  exit 1
fi

# Run tests
TOTAL=0
PASSED=0
FAILED=0
TIMEOUT=0
FAILED_TESTS=""

for hex_file in $TESTS; do
  test_name=$(basename "$hex_file" .hex)

  printf "  %-35s " "$test_name..."
  TOTAL=$((TOTAL + 1))

  # Compile testbench
  IVERILOG_OPTS="-g2012 -I$RTL_DIR -DCOMPLIANCE_TEST -DMEM_FILE=\"$hex_file\""
  if [ "$DEBUG_FPU" = "1" ]; then
    IVERILOG_OPTS="$IVERILOG_OPTS -DDEBUG_FPU"
  fi
  if [ "$DEBUG_FPU_CONVERTER" = "1" ]; then
    IVERILOG_OPTS="$IVERILOG_OPTS -DDEBUG_FPU_CONVERTER"
  fi

  iverilog $IVERILOG_OPTS \
    -o "$SIM_DIR/test_${test_name}.vvp" \
    "$RTL_DIR"/core/*.v \
    "$RTL_DIR"/memory/*.v \
    "$TB_DIR"/integration/tb_core_pipelined.v \
    2>&1 | grep -v "warning:" > "$SIM_DIR/test_${test_name}_compile.log" || true

  # Check compilation
  if [ ! -f "$SIM_DIR/test_${test_name}.vvp" ]; then
    echo -e "${RED}COMPILE FAILED${NC}"
    FAILED=$((FAILED + 1))
    FAILED_TESTS="$FAILED_TESTS\n    - $test_name (compile error)"
    continue
  fi

  # Run simulation with timeout
  timeout 10s vvp "$SIM_DIR/test_${test_name}.vvp" > "$SIM_DIR/test_${test_name}.log" 2>&1 || true

  # Check result
  if grep -q "TEST PASSED" "$SIM_DIR/test_${test_name}.log" 2>/dev/null; then
    echo -e "${GREEN}PASSED${NC}"
    PASSED=$((PASSED + 1))
  elif grep -q "TEST FAILED" "$SIM_DIR/test_${test_name}.log" 2>/dev/null; then
    echo -e "${RED}FAILED${NC}"
    FAILED=$((FAILED + 1))
    FAILED_TESTS="$FAILED_TESTS\n    - $test_name"
  else
    echo -e "${YELLOW}TIMEOUT${NC}"
    TIMEOUT=$((TIMEOUT + 1))
    FAILED_TESTS="$FAILED_TESTS\n    - $test_name (timeout)"
  fi
done

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total:   $TOTAL"
echo -e "${GREEN}Passed:  $PASSED${NC}"
echo -e "${RED}Failed:  $FAILED${NC}"
echo -e "${YELLOW}Timeout: $TIMEOUT${NC}"

if [ $TOTAL -gt 0 ]; then
  PASS_RATE=$((PASSED * 100 / TOTAL))
  echo "Pass rate: ${PASS_RATE}%"
fi

if [ $((FAILED + TIMEOUT)) -gt 0 ]; then
  echo ""
  echo "Failed/Timeout tests:"
  echo -e "$FAILED_TESTS"
  echo ""
  echo "Logs in: $SIM_DIR/test_*.log"
fi

echo ""

# Exit with appropriate code
if [ $PASSED -eq $TOTAL ]; then
  exit 0
else
  exit 1
fi
