#!/bin/bash
# run_rv64_tests.sh - Run RV64 official compliance tests
# Usage: ./tools/run_rv64_tests.sh [extension]
# Extensions: ui, um, ua, uf, ud, uc, all

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RV1_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$RV1_DIR/riscv-tests/isa"
OUTPUT_DIR="$RV1_DIR/tests/official-compliance"
SIM_DIR="$RV1_DIR/sim"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$SIM_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default extension
EXT="${1:-ui}"

echo "========================================"
echo "RV64 Compliance Test Runner"
echo "========================================"
echo "Extension: RV64$EXT"
echo ""

# Get list of tests for the extension
case "$EXT" in
  ui)
    TESTS=$(ls "$TEST_DIR"/rv64ui-p-* 2>/dev/null | grep -v "\.dump$" | sort)
    ;;
  um)
    TESTS=$(ls "$TEST_DIR"/rv64um-p-* 2>/dev/null | grep -v "\.dump$" | sort)
    ;;
  ua)
    TESTS=$(ls "$TEST_DIR"/rv64ua-p-* 2>/dev/null | grep -v "\.dump$" | sort)
    ;;
  uf)
    TESTS=$(ls "$TEST_DIR"/rv64uf-p-* 2>/dev/null | grep -v "\.dump$" | sort)
    ;;
  ud)
    TESTS=$(ls "$TEST_DIR"/rv64ud-p-* 2>/dev/null | grep -v "\.dump$" | sort)
    ;;
  uc)
    TESTS=$(ls "$TEST_DIR"/rv64uc-p-* 2>/dev/null | grep -v "\.dump$" | sort)
    ;;
  all)
    echo "Running ALL RV64 tests..."
    for ext in ui um ua uf ud uc; do
      echo ""
      $0 $ext
    done
    exit 0
    ;;
  *)
    echo "Unknown extension: $EXT"
    echo "Usage: $0 [ui|um|ua|uf|ud|uc|all]"
    exit 1
    ;;
esac

if [ -z "$TESTS" ]; then
  echo "${RED}No tests found for RV64$EXT${NC}"
  exit 1
fi

TOTAL=0
PASSED=0
FAILED=0
TIMEOUT=0

for test_elf in $TESTS; do
  test_name=$(basename "$test_elf")
  test_short="${test_name#rv64*-p-}"

  TOTAL=$((TOTAL + 1))

  # Convert ELF to hex (using correct method: binary + hexdump)
  hex_file="$OUTPUT_DIR/$test_name.hex"
  bin_file="$OUTPUT_DIR/$test_name.bin"

  riscv64-unknown-elf-objcopy -O binary "$test_elf" "$bin_file" 2>/dev/null
  if [ ! -f "$bin_file" ]; then
    echo "${RED}❌ SKIP: $test_short (objcopy failed)${NC}"
    FAILED=$((FAILED + 1))
    continue
  fi

  hexdump -v -e '1/1 "%02x\n"' "$bin_file" > "$hex_file"
  rm -f "$bin_file"

  # Compile testbench
  vvp_file="$SIM_DIR/test_${test_name}.vvp"
  iverilog -g2012 \
    -DCOMPLIANCE_TEST \
    -DMEM_FILE=\"$hex_file\" \
    -I "$RV1_DIR/rtl/" \
    -o "$vvp_file" \
    "$RV1_DIR/rtl/core/"*.v \
    "$RV1_DIR/rtl/memory/"*.v \
    "$RV1_DIR/tb/integration/tb_core_pipelined_rv64.v" \
    > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    echo "${RED}❌ FAIL: $test_short (compilation error)${NC}"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Run simulation
  log_file="$SIM_DIR/test_${test_name}.log"
  timeout 10s vvp "$vvp_file" > "$log_file" 2>&1
  result=$?

  # Check result
  if grep -q "RISC-V COMPLIANCE TEST PASSED" "$log_file" 2>/dev/null; then
    cycles=$(grep "Cycles:" "$log_file" | awk '{print $2}')
    echo "${GREEN}✅ PASS: $test_short${NC} (${cycles} cycles)"
    PASSED=$((PASSED + 1))
  elif grep -q "RISC-V COMPLIANCE TEST FAILED" "$log_file" 2>/dev/null; then
    failed_test=$(grep "Failed at test:" "$log_file" | awk '{print $4}')
    echo "${RED}❌ FAIL: $test_short${NC} (test #$failed_test)"
    FAILED=$((FAILED + 1))
  elif [ $result -eq 124 ]; then
    echo "${YELLOW}⏱️  TIMEOUT: $test_short${NC}"
    TIMEOUT=$((TIMEOUT + 1))
    FAILED=$((FAILED + 1))
  else
    echo "${YELLOW}❓ UNKNOWN: $test_short${NC}"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "========================================"
echo "Results: ${GREEN}$PASSED${NC}/$TOTAL passed, ${RED}$FAILED${NC} failed"
if [ $TIMEOUT -gt 0 ]; then
  echo "  (${YELLOW}$TIMEOUT timeouts${NC})"
fi
echo "========================================"

# Exit with error if any tests failed
if [ $FAILED -gt 0 ]; then
  exit 1
fi
