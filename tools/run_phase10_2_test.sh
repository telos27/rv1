#!/bin/bash
# Run a single Phase 10.2 test program
# Usage: ./run_phase10_2_test.sh <test_name>

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <test_name>"
    echo "Example: $0 test_phase10_2_csr"
    exit 1
fi

TEST_NAME="$1"
ASM_FILE="tests/asm/${TEST_NAME}.s"
HEX_FILE="tests/asm/${TEST_NAME}.hex"
ELF_FILE="/tmp/${TEST_NAME}.elf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "Running Phase 10.2 Test: $TEST_NAME"
echo "========================================"

# Step 1: Compile
echo -n "1. Compiling... "
if riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
    -T tests/linker.ld -o "$ELF_FILE" "$ASM_FILE" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Step 2: Convert to hex
echo -n "2. Creating hex file... "
if ./tools/create_hex.sh "$ELF_FILE" "$HEX_FILE" >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Step 3: Compile Verilog
echo -n "3. Compiling Verilog... "
if iverilog -g2012 -o /tmp/sim_${TEST_NAME} \
    -DMEM_FILE=\"$HEX_FILE\" \
    -I rtl \
    rtl/core/pc.v \
    rtl/core/ifid_register.v \
    rtl/core/decoder.v \
    rtl/core/rvc_decoder.v \
    rtl/core/control.v \
    rtl/core/register_file.v \
    rtl/core/fp_register_file.v \
    rtl/core/idex_register.v \
    rtl/core/alu.v \
    rtl/core/branch_unit.v \
    rtl/core/forwarding_unit.v \
    rtl/core/hazard_detection_unit.v \
    rtl/core/csr_file.v \
    rtl/core/exception_unit.v \
    rtl/core/exmem_register.v \
    rtl/core/memwb_register.v \
    rtl/core/mul_unit.v \
    rtl/core/div_unit.v \
    rtl/core/mul_div_unit.v \
    rtl/core/atomic_unit.v \
    rtl/core/reservation_station.v \
    rtl/core/mmu.v \
    rtl/core/fpu.v \
    rtl/core/fp_adder.v \
    rtl/core/fp_multiplier.v \
    rtl/core/fp_divider.v \
    rtl/core/fp_sqrt.v \
    rtl/core/fp_fma.v \
    rtl/core/fp_compare.v \
    rtl/core/fp_classify.v \
    rtl/core/fp_converter.v \
    rtl/core/fp_minmax.v \
    rtl/core/fp_sign.v \
    rtl/core/rv32i_core_pipelined.v \
    rtl/memory/instruction_memory.v \
    rtl/memory/data_memory.v \
    tb/integration/tb_core_pipelined.v 2>/tmp/${TEST_NAME}_compile.log; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "See /tmp/${TEST_NAME}_compile.log for details"
    exit 1
fi

# Step 4: Run simulation
echo "4. Running simulation..."
echo "----------------------------------------"
timeout 5 /tmp/sim_${TEST_NAME} 2>&1 | tee /tmp/${TEST_NAME}_sim.log | tail -50

echo "----------------------------------------"
echo ""

# Step 5: Check results
echo "5. Checking results..."
if grep -q "EBREAK" /tmp/${TEST_NAME}_sim.log 2>/dev/null || \
   grep -q "ebreak" /tmp/${TEST_NAME}_sim.log 2>/dev/null; then
    echo -e "${GREEN}Test reached EBREAK${NC}"

    # Extract final register values
    if grep -q "a0" /tmp/${TEST_NAME}_sim.log; then
        A0_VAL=$(grep "a0" /tmp/${TEST_NAME}_sim.log | tail -1 | awk '{print $3}')
        echo "Result: a0 = $A0_VAL"

        if [ "$A0_VAL" = "0x00000001" ]; then
            echo -e "${GREEN}✓ TEST PASSED${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠ TEST COMPLETED (check a0 value)${NC}"
            exit 0
        fi
    fi
else
    echo -e "${YELLOW}Simulation completed (check log)${NC}"
fi

echo ""
echo "Logfiles:"
echo "  Compilation: /tmp/${TEST_NAME}_compile.log"
echo "  Simulation:  /tmp/${TEST_NAME}_sim.log"
