#!/bin/bash
# test_pipelined.sh - Run pipelined core tests with configuration support
# Supports both RV32I and RV64I testing

set -e

# Configuration
XLEN=${XLEN:-32}
TEST_NAME=${1:-"simple_add"}
TEST_DIR="tests/asm"
HEX_FILE="${TEST_DIR}/${TEST_NAME}.hex"
SIM_DIR="sim"
WAVES_DIR="${SIM_DIR}/waves"

# Debug flags (passed as -D to iverilog)
DEBUG_FLAGS=""
if [ ! -z "$DEBUG_FPU" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_FPU"
fi
if [ ! -z "$DEBUG_M" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_M"
fi
if [ ! -z "$DEBUG_HAZARD" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_HAZARD"
fi
if [ ! -z "$DEBUG_CSR" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_CSR"
fi
if [ ! -z "$DEBUG_PRIV" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_PRIV"
fi

# Determine architecture
# NOTE: We enable all extensions (IMAFDC) to match how tests are compiled
if [ "$XLEN" = "64" ]; then
    CONFIG_FLAG="-DCONFIG_RV64I -DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1"
    TESTBENCH="tb/integration/tb_core_pipelined_rv64.v"
    OUTPUT_VCD="${WAVES_DIR}/core_pipelined_rv64.vcd"
    OUTPUT_VVP="${SIM_DIR}/rv64i_pipelined.vvp"
    ARCH_NAME="RV64I"
else
    # Enable all extensions to match test compilation (rv32imafc)
    CONFIG_FLAG="-DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1"
    TESTBENCH="tb/integration/tb_core_pipelined.v"
    OUTPUT_VCD="${WAVES_DIR}/core_pipelined.vcd"
    OUTPUT_VVP="${SIM_DIR}/rv32i_pipelined.vvp"
    ARCH_NAME="RV32I"
fi

# Create directories
mkdir -p "$SIM_DIR"
mkdir -p "$WAVES_DIR"

echo "========================================"
echo "$ARCH_NAME Pipelined Core Test Runner"
echo "========================================"
echo "Test: $TEST_NAME"
echo "Hex file: $HEX_FILE"
echo ""

# Check if hex file exists
if [ ! -f "$HEX_FILE" ]; then
    echo "Error: Hex file not found: $HEX_FILE"
    echo "Please compile the test first"
    exit 1
fi

# Step 1: Compile with Icarus Verilog
echo "Step 1: Compiling with Icarus Verilog ($ARCH_NAME configuration)..."
if [ ! -z "$DEBUG_FLAGS" ]; then
    echo "Debug flags: $DEBUG_FLAGS"
fi
iverilog -g2012 \
    -I rtl \
    $CONFIG_FLAG \
    $DEBUG_FLAGS \
    -DMEM_FILE=\"$HEX_FILE\" \
    -o "$OUTPUT_VVP" \
    rtl/core/*.v \
    rtl/memory/*.v \
    "$TESTBENCH"

if [ $? -ne 0 ]; then
    echo "✗ Compilation failed"
    exit 1
fi

echo "✓ Compilation successful"
echo ""

# Step 2: Run simulation
echo "Step 2: Running simulation..."
echo "----------------------------------------"
vvp "$OUTPUT_VVP"

if [ $? -eq 0 ]; then
    echo "----------------------------------------"
    echo ""
    echo "✓ Test completed"
    echo ""
    echo "Waveform: $OUTPUT_VCD"
    echo "To view: gtkwave $OUTPUT_VCD"
else
    echo "✗ Test failed"
    exit 1
fi
