#!/bin/bash
# run_compliance.sh - Run RISC-V compliance tests
# Author: RV1 Project
# Date: 2025-10-09

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories
RV1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RISCV_TESTS_DIR="/tmp/riscv-tests/isa"
COMPLIANCE_DIR="$RV1_DIR/tests/riscv-compliance"
SIM_DIR="$RV1_DIR/sim"
RTL_DIR="$RV1_DIR/rtl"
TB_DIR="$RV1_DIR/tb"

# Create directories
mkdir -p "$COMPLIANCE_DIR"
mkdir -p "$SIM_DIR/compliance"

echo "========================================"
echo "RISC-V Compliance Test Runner (Pipelined)"
echo "========================================"
echo ""

# Step 1: Convert all tests to hex format
echo "Step 1: Converting tests to hex format..."
cd "$RISCV_TESTS_DIR"

test_count=0
for test_bin in rv32ui-p-*; do
  # Skip dump files
  if [[ "$test_bin" == *.dump ]]; then
    continue
  fi

  test_name=$(basename "$test_bin")
  hex_file="$COMPLIANCE_DIR/${test_name}.hex"

  # Clean up old binary file if it exists
  rm -f "${test_bin}.bin"

  # Convert ELF to binary, then to byte-wise hex (for $readmemh with byte array)
  riscv64-unknown-elf-objcopy -O binary "$test_bin" "${test_bin}.bin" 2>/dev/null
  hexdump -v -e '1/1 "%02x\n"' "${test_bin}.bin" > "$hex_file"
  rm -f "${test_bin}.bin"

  test_count=$((test_count + 1))
  echo "  Converted: $test_name -> ${test_name}.hex"
done

echo ""
echo "Converted $test_count tests to hex format"
echo ""

# Step 2: Run each test
echo "Step 2: Running compliance tests..."
echo ""

passed=0
failed=0
failed_tests=""

cd "$RV1_DIR"

for hex_file in "$COMPLIANCE_DIR"/rv32ui-p-*.hex; do
  test_name=$(basename "$hex_file" .hex)

  echo -n "Running $test_name... "

  # Run simulation (using pipelined core)
  iverilog -g2012 \
    -I"$RTL_DIR" \
    -DCOMPLIANCE_TEST \
    -DMEM_FILE="\"$hex_file\"" \
    -o "$SIM_DIR/compliance/${test_name}.vvp" \
    "$RTL_DIR/core"/*.v \
    "$RTL_DIR/memory"/*.v \
    "$TB_DIR/integration/tb_core_pipelined.v" \
    2>&1 | grep -v "warning" > "$SIM_DIR/compliance/${test_name}_compile.log" || true

  # Check compilation
  if [ ! -f "$SIM_DIR/compliance/${test_name}.vvp" ]; then
    echo -e "${RED}COMPILE FAILED${NC}"
    failed=$((failed + 1))
    failed_tests="$failed_tests\n  - $test_name (compilation failed)"
    continue
  fi

  # Run simulation
  vvp "$SIM_DIR/compliance/${test_name}.vvp" > "$SIM_DIR/compliance/${test_name}.log" 2>&1

  # Check result
  if grep -q "RISC-V COMPLIANCE TEST PASSED" "$SIM_DIR/compliance/${test_name}.log"; then
    echo -e "${GREEN}PASSED${NC}"
    passed=$((passed + 1))
  elif grep -q "RISC-V COMPLIANCE TEST FAILED" "$SIM_DIR/compliance/${test_name}.log"; then
    # Extract failure info
    fail_num=$(grep "Failed at test number:" "$SIM_DIR/compliance/${test_name}.log" | awk '{print $NF}')
    echo -e "${RED}FAILED (test #$fail_num)${NC}"
    failed=$((failed + 1))
    failed_tests="$failed_tests\n  - $test_name (failed at test #$fail_num)"
  else
    echo -e "${YELLOW}TIMEOUT/ERROR${NC}"
    failed=$((failed + 1))
    failed_tests="$failed_tests\n  - $test_name (timeout or error)"
  fi
done

# Step 3: Summary
echo ""
echo "========================================"
echo "COMPLIANCE TEST SUMMARY"
echo "========================================"
echo "Total tests: $test_count"
echo -e "${GREEN}Passed: $passed${NC}"
echo -e "${RED}Failed: $failed${NC}"

if [ $failed -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  echo -e "$failed_tests"
fi

echo ""

# Calculate percentage
if [ $test_count -gt 0 ]; then
  pass_rate=$((passed * 100 / test_count))
  echo "Pass rate: ${pass_rate}%"

  if [ $pass_rate -ge 90 ]; then
    echo -e "${GREEN}✓ Target achieved (≥90%)${NC}"
  else
    echo -e "${YELLOW}⚠ Target not met (≥90%)${NC}"
  fi
fi

echo ""
echo "Logs saved to: $SIM_DIR/compliance/"
echo ""

# Exit with error if tests failed
if [ $failed -gt 0 ]; then
  exit 1
fi
