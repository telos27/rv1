#!/bin/bash
# test_clint.sh - Run CLINT testbench
# Author: RV1 Project
# Date: 2025-10-26

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "CLINT Testbench Runner"
echo "========================================"

# Directories
RTL_DIR="rtl"
TB_DIR="tb"
SIM_DIR="sim"
WAVE_DIR="$SIM_DIR/waves"

# Create directories if they don't exist
mkdir -p "$SIM_DIR"
mkdir -p "$WAVE_DIR"

# Compile
echo ""
echo "Compiling CLINT module and testbench..."
iverilog -g2012 \
  -I "$RTL_DIR" \
  -o "$SIM_DIR/tb_clint.vvp" \
  "$RTL_DIR/peripherals/clint.v" \
  "$TB_DIR/peripherals/tb_clint.v"

if [ $? -ne 0 ]; then
  echo -e "${RED}Compilation failed!${NC}"
  exit 1
fi

echo -e "${GREEN}Compilation successful${NC}"

# Run simulation
echo ""
echo "Running simulation..."
cd "$SIM_DIR"
vvp tb_clint.vvp | tee clint_test.log
SIM_RESULT=$?
cd ..

# Check result
echo ""
if [ $SIM_RESULT -eq 0 ]; then
  if grep -q "ALL TESTS PASSED" "$SIM_DIR/clint_test.log"; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ CLINT TESTS PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
  else
    echo -e "${YELLOW}Simulation completed but test status unclear${NC}"
    exit 1
  fi
else
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}✗ CLINT TESTS FAILED${NC}"
  echo -e "${RED}========================================${NC}"
  exit 1
fi

# Optional: View waveform
if command -v gtkwave &> /dev/null; then
  echo ""
  echo "Waveform saved to: $WAVE_DIR/tb_clint.vcd"
  echo "To view: gtkwave $WAVE_DIR/tb_clint.vcd"
fi

exit 0
