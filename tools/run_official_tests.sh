#!/bin/bash
# Run official RISC-V compliance tests
# This script converts ELF binaries to hex and runs them through the RV1 core

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
RISCV_TESTS_DIR="$RV1_DIR/riscv-tests/isa"
HEX_DIR="$RV1_DIR/tests/official-compliance"
SIM_DIR="$RV1_DIR/sim/official-compliance"
RTL_DIR="$RV1_DIR/rtl"
TB_DIR="$RV1_DIR/tb"

# Create directories
mkdir -p "$HEX_DIR"
mkdir -p "$SIM_DIR"

# Check if tests exist
if [ ! -d "$RISCV_TESTS_DIR" ]; then
  echo -e "${RED}Error: riscv-tests/isa directory not found${NC}"
  echo "Please run: ./tools/build_riscv_tests.sh first"
  exit 1
fi

# Usage
usage() {
  echo "Usage: $0 [extension] [test_name]"
  echo ""
  echo "Extensions:"
  echo "  i, ui     - RV32I Base Integer"
  echo "  m, um     - M Extension (Multiply/Divide)"
  echo "  a, ua     - A Extension (Atomic)"
  echo "  f, uf     - F Extension (Single-Precision FP)"
  echo "  d, ud     - D Extension (Double-Precision FP)"
  echo "  c, uc     - C Extension (Compressed)"
  echo "  all       - All extensions"
  echo ""
  echo "Examples:"
  echo "  $0 i              # Run all RV32I tests"
  echo "  $0 m              # Run all M extension tests"
  echo "  $0 i add          # Run specific test: rv32ui-p-add"
  echo "  $0 all            # Run all tests"
  exit 1
}

# Convert extension shorthand to full name
get_extension() {
  case "$1" in
    i|ui) echo "rv32ui" ;;
    m|um) echo "rv32um" ;;
    a|ua) echo "rv32ua" ;;
    f|uf) echo "rv32uf" ;;
    d|ud) echo "rv32ud" ;;
    c|uc) echo "rv32uc" ;;
    all)  echo "all" ;;
    *)    echo "unknown" ;;
  esac
}

# Convert ELF to hex
elf_to_hex() {
  local elf_file="$1"
  local hex_file="$2"

  # Convert to binary first
  riscv64-unknown-elf-objcopy -O binary "$elf_file" "${elf_file}.bin" 2>/dev/null

  # Convert to byte-wise hex (for $readmemh with byte array)
  hexdump -v -e '1/1 "%02x\n"' "${elf_file}.bin" > "$hex_file"

  # Clean up
  rm -f "${elf_file}.bin"
}

# Run a single test
run_test() {
  local test_path="$1"
  local test_name=$(basename "$test_path")

  # Convert to hex if needed
  local hex_file="$HEX_DIR/${test_name}.hex"
  if [ ! -f "$hex_file" ] || [ "$test_path" -nt "$hex_file" ]; then
    elf_to_hex "$test_path" "$hex_file"
  fi

  # Compile testbench
  iverilog -g2012 \
    -I"$RTL_DIR" \
    -DCOMPLIANCE_TEST \
    -DMEM_FILE="\"$hex_file\"" \
    -o "$SIM_DIR/${test_name}.vvp" \
    "$RTL_DIR"/core/*.v \
    "$RTL_DIR"/memory/*.v \
    "$TB_DIR"/integration/tb_core_pipelined.v \
    2>&1 | grep -v "warning" > "$SIM_DIR/${test_name}_compile.log" || true

  # Check compilation
  if [ ! -f "$SIM_DIR/${test_name}.vvp" ]; then
    echo -e "${RED}COMPILE FAILED${NC}"
    return 1
  fi

  # Run simulation
  timeout 10s vvp "$SIM_DIR/${test_name}.vvp" > "$SIM_DIR/${test_name}.log" 2>&1 || true

  # Check result
  if grep -q "TEST PASSED" "$SIM_DIR/${test_name}.log"; then
    echo -e "${GREEN}PASSED${NC}"
    return 0
  elif grep -q "TEST FAILED" "$SIM_DIR/${test_name}.log"; then
    local gp_val=$(grep "gp =" "$SIM_DIR/${test_name}.log" | tail -1 | awk '{print $NF}')
    echo -e "${RED}FAILED (gp=$gp_val)${NC}"
    return 1
  else
    echo -e "${YELLOW}TIMEOUT/ERROR${NC}"
    return 1
  fi
}

# Main logic
if [ $# -eq 0 ]; then
  usage
fi

EXT_ARG="$1"
TEST_ARG="${2:-}"

EXT=$(get_extension "$EXT_ARG")
if [ "$EXT" = "unknown" ]; then
  echo -e "${RED}Error: Unknown extension '$EXT_ARG'${NC}"
  usage
fi

echo "=========================================="
echo "RV1 Official RISC-V Compliance Tests"
echo "=========================================="
echo ""

# Determine which tests to run
if [ "$EXT" = "all" ]; then
  EXTENSIONS="rv32ui rv32um rv32ua rv32uf rv32ud rv32uc"
else
  EXTENSIONS="$EXT"
fi

# Run tests
TOTAL=0
PASSED=0
FAILED=0
FAILED_TESTS=""

for ext in $EXTENSIONS; do
  echo -e "${BLUE}Testing $ext...${NC}"
  echo ""

  # Get list of tests
  if [ -n "$TEST_ARG" ]; then
    # Specific test
    TEST_LIST=$(ls "$RISCV_TESTS_DIR/${ext}-p-${TEST_ARG}" 2>/dev/null | grep -v "\.dump$" || true)
    if [ -z "$TEST_LIST" ]; then
      echo -e "${YELLOW}Test ${ext}-p-${TEST_ARG} not found${NC}"
      continue
    fi
  else
    # All tests for this extension
    TEST_LIST=$(ls "$RISCV_TESTS_DIR/${ext}-p-"* 2>/dev/null | grep -v "\.dump$" || true)
    if [ -z "$TEST_LIST" ]; then
      echo -e "${YELLOW}No tests found for $ext${NC}"
      continue
    fi
  fi

  # Run each test
  for test in $TEST_LIST; do
    test_name=$(basename "$test")
    printf "  %-30s " "$test_name..."

    TOTAL=$((TOTAL + 1))
    if run_test "$test"; then
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
      FAILED_TESTS="$FAILED_TESTS\n    - $test_name"
    fi
  done

  echo ""
done

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total:  $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"

if [ $TOTAL -gt 0 ]; then
  PASS_RATE=$((PASSED * 100 / TOTAL))
  echo "Pass rate: ${PASS_RATE}%"
fi

if [ $FAILED -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  echo -e "$FAILED_TESTS"
  echo ""
  echo "Logs in: $SIM_DIR/"
fi

echo ""

# Exit with error if tests failed
if [ $FAILED -gt 0 ]; then
  exit 1
fi
