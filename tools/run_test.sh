#!/bin/bash
# run_test.sh - Run a single test program on the RV1 core

set -e

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <test_name> [timeout_cycles]"
    echo "Example: $0 fibonacci 10000"
    exit 1
fi

TEST_NAME=$1
TIMEOUT=${2:-10000}

# Files
HEX_FILE="tests/vectors/${TEST_NAME}.hex"
VVP_FILE="sim/test_${TEST_NAME}.vvp"
LOG_FILE="sim/${TEST_NAME}.log"
WAVE_FILE="sim/waves/${TEST_NAME}.vcd"

# Check if hex file exists
if [ ! -f "$HEX_FILE" ]; then
    echo "Error: Test hex file not found: $HEX_FILE"
    echo "Did you run: make asm-tests or tools/assemble.sh tests/asm/${TEST_NAME}.s?"
    exit 1
fi

# Create directories if needed
mkdir -p sim/waves

# RTL files
RTL_CORE="rtl/core/*.v"
RTL_MEM="rtl/memory/*.v"
TB_FILE="tb/integration/tb_core.v"

echo "Running test: $TEST_NAME"
echo "Hex file: $HEX_FILE"
echo "Timeout: $TIMEOUT cycles"
echo ""

# Compile
echo "Compiling..."
iverilog -g2012 \
    -DMEM_FILE=\"$HEX_FILE\" \
    -DTIMEOUT=$TIMEOUT \
    -o "$VVP_FILE" \
    $RTL_CORE $RTL_MEM $TB_FILE

# Run simulation
echo "Running simulation..."
vvp "$VVP_FILE" > "$LOG_FILE" 2>&1

# Check results
echo ""
if grep -q "PASS\|Test PASSED" "$LOG_FILE"; then
    echo "✓ Test $TEST_NAME PASSED"

    # Extract key results if available
    if grep -q "Result" "$LOG_FILE"; then
        grep "Result" "$LOG_FILE"
    fi

    exit 0
else
    echo "✗ Test $TEST_NAME FAILED"
    echo ""
    echo "Log output:"
    cat "$LOG_FILE"

    if [ -f "$WAVE_FILE" ]; then
        echo ""
        echo "Waveform saved to: $WAVE_FILE"
        echo "View with: gtkwave $WAVE_FILE"
    fi

    exit 1
fi
