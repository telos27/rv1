#!/bin/bash
# test_soc.sh - Run SoC tests (core + peripherals including CLINT)
# Tests can access CLINT memory-mapped registers for interrupt testing
# Based on test_pipelined.sh but uses tb_soc.v

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
if [ ! -z "$DEBUG_CSR_FORWARD" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_CSR_FORWARD"
fi
if [ ! -z "$DEBUG_PRIV" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_PRIV"
fi
if [ ! -z "$DEBUG_EXCEPTION" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_EXCEPTION"
fi
if [ ! -z "$DEBUG_CLINT" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_CLINT"
fi
if [ ! -z "$DEBUG_INTERRUPT" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_INTERRUPT"
fi
if [ ! -z "$DEBUG_UART_BUS" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_UART_BUS"
fi
if [ ! -z "$DEBUG_UART_CORE" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_UART_CORE"
fi
if [ ! -z "$DEBUG_BUS" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_BUS"
fi
if [ ! -z "$DEBUG_PC_TRACE" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_PC_TRACE"
fi

# SoC test configuration
# Enable all extensions to match test compilation (rv32imafc)
CONFIG_FLAG="-DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1"
TESTBENCH="tb/integration/tb_soc.v"
OUTPUT_VCD="${WAVES_DIR}/soc.vcd"
OUTPUT_VVP="${SIM_DIR}/soc.vvp"
ARCH_NAME="RV32IMAFDC SoC"

# Create directories
mkdir -p "$SIM_DIR"
mkdir -p "$WAVES_DIR"

echo "========================================"
echo "$ARCH_NAME Test Runner"
echo "========================================"
echo "Test: $TEST_NAME"
echo "Hex file: $HEX_FILE"
echo ""

# Auto-rebuild hex file if missing or stale
ASM_FILE="${TEST_DIR}/${TEST_NAME}.s"

if [ ! -f "$HEX_FILE" ]; then
    # Hex file missing - try to build it
    if [ -f "$ASM_FILE" ]; then
        echo "Hex file missing, building from source: $ASM_FILE"
        if ! ./tools/asm_to_hex.sh "$ASM_FILE" 2>&1 | tail -5; then
            echo ""
            echo "Error: Failed to build $HEX_FILE"
            echo "This test may require extensions not available in your toolchain"
            exit 1
        fi
        echo ""
    else
        echo "Error: Neither hex file nor source found"
        echo "  Hex:    $HEX_FILE"
        echo "  Source: $ASM_FILE"
        exit 1
    fi
elif [ -f "$ASM_FILE" ] && [ "$ASM_FILE" -nt "$HEX_FILE" ]; then
    # Source is newer than hex - rebuild
    echo "Source modified, rebuilding: $ASM_FILE"
    if ! ./tools/asm_to_hex.sh "$ASM_FILE" 2>&1 | tail -5; then
        echo ""
        echo "Error: Failed to rebuild $HEX_FILE"
        echo "This test may require extensions not available in your toolchain"
        exit 1
    fi
    echo ""
fi

# Step 1: Compile with Icarus Verilog
echo "Step 1: Compiling SoC with Icarus Verilog..."
echo "  Config: $CONFIG_FLAG $DEBUG_FLAGS"
echo "  Testbench: $TESTBENCH"
echo "  Memory file: $HEX_FILE"
echo ""

# Include all RTL directories for SoC
iverilog -g2012 \
    $CONFIG_FLAG \
    $DEBUG_FLAGS \
    -DCOMPLIANCE_TEST \
    -DMEM_INIT_FILE=\"$HEX_FILE\" \
    -I rtl/ \
    -I rtl/core/ \
    -I rtl/memory/ \
    -I rtl/peripherals/ \
    -I rtl/interconnect/ \
    -I rtl/config/ \
    -I external/wbuart32/rtl/ \
    -o "$OUTPUT_VVP" \
    rtl/rv_soc.v \
    rtl/core/*.v \
    rtl/memory/*.v \
    rtl/peripherals/*.v \
    rtl/interconnect/*.v \
    "$TESTBENCH"

if [ $? -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "COMPILATION FAILED"
    echo "========================================"
    exit 1
fi

echo "✓ Compilation successful"
echo ""

# Step 2: Run simulation
echo "Step 2: Running simulation..."
echo ""

vvp "$OUTPUT_VVP" -lxt2

if [ $? -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "SIMULATION FAILED (crashed)"
    echo "========================================"
    exit 1
fi

echo ""
echo "✓ Test completed"
echo ""
echo "Waveform: $OUTPUT_VCD"
echo "To view: gtkwave $OUTPUT_VCD"
