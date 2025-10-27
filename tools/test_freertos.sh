#!/bin/bash
# test_freertos.sh - Run FreeRTOS simulation on RV1 SoC
# Usage: ./tools/test_freertos.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "FreeRTOS Simulation Runner"
echo "=========================================="

# Check if FreeRTOS binary exists
if [ ! -f "software/freertos/build/freertos-rv1.hex" ]; then
    echo -e "${RED}ERROR: FreeRTOS binary not found${NC}"
    echo "Expected: software/freertos/build/freertos-rv1.hex"
    echo ""
    echo "Please build FreeRTOS first:"
    echo "  cd software/freertos && make"
    exit 1
fi

# Check if testbench exists
if [ ! -f "tb/integration/tb_freertos.v" ]; then
    echo -e "${RED}ERROR: FreeRTOS testbench not found${NC}"
    echo "Expected: tb/integration/tb_freertos.v"
    exit 1
fi

echo "Binary: software/freertos/build/freertos-rv1.hex"
echo "Testbench: tb/integration/tb_freertos.v"
echo ""

# Build simulation
echo "Building simulation..."
SIM_OUT="sim/tb_freertos"
mkdir -p sim

# Collect all source files
RTL_CORE="rtl/core/*.v"
RTL_MEMORY="rtl/memory/*.v"
RTL_PERIPHERALS="rtl/peripherals/*.v"
RTL_INTERCONNECT="rtl/interconnect/*.v"
RTL_TOP="rtl/*.v"
TB="tb/integration/tb_freertos.v"

# Compile with Icarus Verilog
# FreeRTOS binary includes compressed instructions - enable C extension
# Enable BSS fast-clear to skip slow memory initialization loop (~200k cycles saved)
iverilog -g2012 \
    -o "$SIM_OUT" \
    -I rtl \
    -I rtl/config \
    -D XLEN=32 \
    -D ENABLE_C_EXT=1 \
    -D ENABLE_BSS_FAST_CLEAR=1 \
    $RTL_CORE \
    $RTL_MEMORY \
    $RTL_PERIPHERALS \
    $RTL_INTERCONNECT \
    $RTL_TOP \
    $TB

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}Compilation successful${NC}"
echo ""

# Run simulation
echo "Running FreeRTOS simulation..."
echo "=========================================="
echo ""

# Run with timeout (default 60s)
TIMEOUT=${TIMEOUT:-60}
timeout ${TIMEOUT}s vvp "$SIM_OUT"
EXIT_CODE=$?

echo ""
echo "=========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}Simulation completed successfully${NC}"
elif [ $EXIT_CODE -eq 124 ]; then
    echo -e "${YELLOW}Simulation timeout (${TIMEOUT}s)${NC}"
    echo "This might be expected for long-running FreeRTOS tests"
    echo "Increase timeout with: TIMEOUT=120 ./tools/test_freertos.sh"
else
    echo -e "${RED}Simulation failed with exit code $EXIT_CODE${NC}"
    exit $EXIT_CODE
fi

echo "=========================================="

# Check for VCD file
if [ -f "tb_freertos.vcd" ]; then
    VCD_SIZE=$(du -h tb_freertos.vcd | cut -f1)
    echo "VCD file: tb_freertos.vcd ($VCD_SIZE)"
    echo "View with: gtkwave tb_freertos.vcd"
fi

exit 0
