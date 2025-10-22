#!/bin/bash
# run_single_test.sh - Quick test runner for debugging
# Usage: ./tools/run_single_test.sh <test_name> [debug_flags]
# Example: ./tools/run_single_test.sh rv32uf-p-fcvt_w DEBUG_FPU_CONVERTER

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RV1_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$RV1_DIR/rtl"
TB_DIR="$RV1_DIR/tb"
SIM_DIR="$RV1_DIR/sim"
TEST_DIR="$RV1_DIR/tests/official-compliance"

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <test_name> [debug_flags]"
  echo ""
  echo "Examples:"
  echo "  $0 rv32uf-p-fcvt_w"
  echo "  $0 rv32uf-p-fcvt_w DEBUG_FPU_CONVERTER"
  echo "  $0 rv32uf-p-fadd DEBUG_FPU"
  echo ""
  exit 1
fi

TEST_NAME="$1"
shift

# Build debug flags
DEBUG_FLAGS=""
for flag in "$@"; do
  DEBUG_FLAGS="$DEBUG_FLAGS -D$flag"
done

# Check if test hex exists
HEX_FILE="$TEST_DIR/$TEST_NAME.hex"
if [ ! -f "$HEX_FILE" ]; then
  echo "Error: Test file not found: $HEX_FILE"
  exit 1
fi

# Create sim directory if needed
mkdir -p "$SIM_DIR"

echo "=========================================="
echo "Running Single Test: $TEST_NAME"
echo "=========================================="
echo "Hex file: $HEX_FILE"
echo "Debug flags: ${DEBUG_FLAGS:-none}"
echo ""

# Compile
echo "Compiling..."
VVP_FILE="$SIM_DIR/${TEST_NAME}_debug.vvp"
COMPILE_LOG="$SIM_DIR/${TEST_NAME}_compile.log"

iverilog -g2012 \
  -I"$RTL_DIR" \
  -DCOMPLIANCE_TEST \
  -DMEM_FILE=\"$HEX_FILE\" \
  $DEBUG_FLAGS \
  -o "$VVP_FILE" \
  "$RTL_DIR"/core/*.v \
  "$RTL_DIR"/memory/*.v \
  "$TB_DIR"/integration/tb_core_pipelined.v \
  2>&1 | grep -v "^$\|warning:" | tee "$COMPILE_LOG"

if [ ! -f "$VVP_FILE" ]; then
  echo "Compilation failed! Check $COMPILE_LOG"
  exit 1
fi

echo "Compilation successful"
echo ""

# Run simulation
echo "Running simulation..."
LOG_FILE="$SIM_DIR/${TEST_NAME}_debug.log"

timeout 120s vvp "$VVP_FILE" 2>&1 | tee "$LOG_FILE"

# Check result
echo ""
echo "=========================================="
if grep -q "TEST PASSED" "$LOG_FILE" 2>/dev/null; then
  echo "Result: PASSED ✓"
  exit 0
elif grep -q "TEST FAILED" "$LOG_FILE" 2>/dev/null; then
  FAIL_LINE=$(grep "Failed at test number" "$LOG_FILE" | head -1)
  echo "Result: FAILED ✗"
  echo "$FAIL_LINE"

  # Show final register state
  echo ""
  echo "Final registers:"
  grep -A 3 "x3.*gp" "$LOG_FILE" | tail -4
  grep -A 1 "x10.*a0" "$LOG_FILE" | tail -2
  grep -A 1 "x11.*a1" "$LOG_FILE" | tail -2

  exit 1
else
  echo "Result: TIMEOUT ⏱"
  exit 2
fi
