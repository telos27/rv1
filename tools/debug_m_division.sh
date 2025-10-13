#!/bin/bash
# Debug M Extension Division Bug
# Run DIVU test with detailed debug output

set -e

echo "=== M Extension Division Bug Debug ==="
echo ""

# Check if test file exists
TEST_FILE="riscv-tests/isa/rv32um-p-divu"
if [ ! -f "$TEST_FILE" ]; then
  echo "ERROR: Test file not found: $TEST_FILE"
  echo "Please run: ./tools/build_riscv_tests.sh m"
  exit 1
fi

# Convert to hex
echo "Converting test to hex format..."
mkdir -p tests/official-compliance
riscv64-unknown-elf-objcopy -O binary "$TEST_FILE" "$TEST_FILE.bin"
hexdump -v -e '1/1 "%02x\n"' "$TEST_FILE.bin" > tests/official-compliance/rv32um-p-divu.hex
rm -f "$TEST_FILE.bin"

# Compile with debug flags
echo "Compiling with debug output enabled..."
iverilog -g2012 \
  -Irtl \
  -DCOMPLIANCE_TEST \
  -DMEM_FILE="\"tests/official-compliance/rv32um-p-divu.hex\"" \
  -DDEBUG_DIV \
  -DDEBUG_DIV_STEPS \
  -DDEBUG_MUL_DIV \
  -o sim_m_debug \
  rtl/core/*.v \
  rtl/memory/*.v \
  tb/integration/tb_core_pipelined.v

if [ $? -ne 0 ]; then
  echo "ERROR: Compilation failed"
  exit 1
fi

# Run simulation with timeout
echo ""
echo "Running DIVU test with debug output..."
echo "========================================"
timeout 30 vvp sim_m_debug +MEM_FILE=tests/official-compliance/rv32um-p-divu.hex 2>&1 | tee debug_m_division.log

# Check result
if grep -q "PASSED" debug_m_division.log; then
  echo ""
  echo "✅ TEST PASSED"
  exit 0
elif grep -q "FAILED" debug_m_division.log; then
  echo ""
  echo "❌ TEST FAILED"
  echo ""
  echo "Debug log saved to: debug_m_division.log"
  echo "Key sections to check:"
  echo "  - [ALU] lines: Check ALU result computation"
  echo "  - [EXMEM] lines: Check EX->MEM pipeline register transfer"
  echo "  - [MEMWB] lines: Check MEM->WB pipeline register transfer"
  echo "  - [REGFILE_WB] lines: Check register file writes in WB stage"
  echo "  - [IDEX] lines: Check if IDEX holds properly during M operations"
  echo "  - [FORWARD_*] lines: Check forwarding decisions"
  echo "  - [M_OPERANDS] lines: Check operand values feeding M unit"
  echo "  - [MUL_DIV] lines: Check M unit operation"
  echo "  - [DIV] lines: Check division unit behavior"
  exit 1
else
  echo ""
  echo "⚠️  TEST TIMEOUT OR ERROR"
  exit 1
fi
