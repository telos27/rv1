#!/bin/bash
# Build official RISC-V tests
# This script compiles all extension tests we need for compliance testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RV1_DIR="$(dirname "$SCRIPT_DIR")"
RISCV_TESTS_DIR="$RV1_DIR/riscv-tests"
ISA_DIR="$RISCV_TESTS_DIR/isa"

echo "=========================================="
echo "Building RISC-V Official Test Suite"
echo "=========================================="
echo ""

if [ ! -d "$RISCV_TESTS_DIR" ]; then
  echo "Error: riscv-tests directory not found at $RISCV_TESTS_DIR"
  exit 1
fi

cd "$RISCV_TESTS_DIR"

# Check if configured
if [ ! -f "Makefile" ]; then
  echo "Configuring riscv-tests..."
  ./configure --prefix="$RISCV_TESTS_DIR/install"
fi

# Build only the -p (physical memory) tests for each extension
# The -v (virtual memory) tests require full libc which we don't have
cd "$ISA_DIR"

echo "Building RV32UI (Base Integer) tests..."
make rv32ui-p-simple rv32ui-p-add rv32ui-p-addi rv32ui-p-and rv32ui-p-andi \
     rv32ui-p-auipc rv32ui-p-beq rv32ui-p-bge rv32ui-p-bgeu rv32ui-p-blt \
     rv32ui-p-bltu rv32ui-p-bne rv32ui-p-fence_i rv32ui-p-jal rv32ui-p-jalr \
     rv32ui-p-lb rv32ui-p-lbu rv32ui-p-lh rv32ui-p-lhu rv32ui-p-lw \
     rv32ui-p-lui rv32ui-p-ma_data rv32ui-p-or rv32ui-p-ori rv32ui-p-sb \
     rv32ui-p-sh rv32ui-p-sw rv32ui-p-sll rv32ui-p-slli rv32ui-p-slt \
     rv32ui-p-slti rv32ui-p-sltiu rv32ui-p-sltu rv32ui-p-sra rv32ui-p-srai \
     rv32ui-p-srl rv32ui-p-srli rv32ui-p-sub rv32ui-p-xor rv32ui-p-xori \
     2>/dev/null || true

echo "Building RV32UM (Multiply/Divide) tests..."
make rv32um-p-div rv32um-p-divu rv32um-p-mul rv32um-p-mulh rv32um-p-mulhsu \
     rv32um-p-mulhu rv32um-p-rem rv32um-p-remu \
     2>/dev/null || true

echo "Building RV32UA (Atomic) tests..."
make rv32ua-p-amoadd_w rv32ua-p-amoand_w rv32ua-p-amomax_w rv32ua-p-amomaxu_w \
     rv32ua-p-amomin_w rv32ua-p-amominu_w rv32ua-p-amoor_w rv32ua-p-amoswap_w \
     rv32ua-p-amoxor_w rv32ua-p-lrsc \
     2>/dev/null || true

echo "Building RV32UF (Single-Precision FP) tests..."
make rv32uf-p-fadd rv32uf-p-fclass rv32uf-p-fcmp rv32uf-p-fcvt rv32uf-p-fcvt_w \
     rv32uf-p-fdiv rv32uf-p-fmadd rv32uf-p-fmin rv32uf-p-ldst rv32uf-p-move \
     rv32uf-p-recoding \
     2>/dev/null || true

echo "Building RV32UD (Double-Precision FP) tests..."
make rv32ud-p-fadd rv32ud-p-fclass rv32ud-p-fcmp rv32ud-p-fcvt rv32ud-p-fcvt_w \
     rv32ud-p-fdiv rv32ud-p-fmadd rv32ud-p-fmin rv32ud-p-ldst rv32ud-p-move \
     rv32ud-p-recoding rv32ud-p-structural \
     2>/dev/null || true

echo "Building RV32UC (Compressed Instructions) tests..."
make rv32uc-p-rvc \
     2>/dev/null || true

echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="

count_tests() {
  ls $1 2>/dev/null | grep -v "\.dump$" | wc -l
}

ui_count=$(count_tests "rv32ui-p-*")
um_count=$(count_tests "rv32um-p-*")
ua_count=$(count_tests "rv32ua-p-*")
uf_count=$(count_tests "rv32uf-p-*")
ud_count=$(count_tests "rv32ud-p-*")
uc_count=$(count_tests "rv32uc-p-*")

echo "RV32UI (Base Integer):     $ui_count tests"
echo "RV32UM (Multiply/Divide):  $um_count tests"
echo "RV32UA (Atomic):           $ua_count tests"
echo "RV32UF (Single-FP):        $uf_count tests"
echo "RV32UD (Double-FP):        $ud_count tests"
echo "RV32UC (Compressed):       $uc_count tests"
echo ""

total=$((ui_count + um_count + ua_count + uf_count + ud_count + uc_count))
echo "Total: $total test binaries built"
echo ""

if [ $total -lt 10 ]; then
  echo "WARNING: Very few tests were built. Check for errors above."
  exit 1
fi

echo "Test binaries are in: $ISA_DIR/"
echo ""
