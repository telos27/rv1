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

# RV64 Tests (Session 85: Added for RV64 compliance testing)
if [ "${BUILD_RV64:-}" = "1" ] || [ "${XLEN:-32}" = "64" ]; then
  echo ""
  echo "Building RV64 tests..."

  echo "Building RV64UI (Base Integer) tests..."
  make rv64ui-p-add rv64ui-p-addi rv64ui-p-addiw rv64ui-p-addw \
       rv64ui-p-and rv64ui-p-andi rv64ui-p-auipc rv64ui-p-beq \
       rv64ui-p-bge rv64ui-p-bgeu rv64ui-p-blt rv64ui-p-bltu \
       rv64ui-p-bne rv64ui-p-fence_i rv64ui-p-jal rv64ui-p-jalr \
       rv64ui-p-lb rv64ui-p-lbu rv64ui-p-ld rv64ui-p-lh \
       rv64ui-p-lhu rv64ui-p-lui rv64ui-p-lw rv64ui-p-lwu \
       rv64ui-p-or rv64ui-p-ori rv64ui-p-sb rv64ui-p-sd \
       rv64ui-p-sh rv64ui-p-sll rv64ui-p-slli rv64ui-p-slliw \
       rv64ui-p-sllw rv64ui-p-slt rv64ui-p-slti rv64ui-p-sltiu \
       rv64ui-p-sltu rv64ui-p-sra rv64ui-p-srai rv64ui-p-sraiw \
       rv64ui-p-sraw rv64ui-p-srl rv64ui-p-srli rv64ui-p-srliw \
       rv64ui-p-srlw rv64ui-p-sub rv64ui-p-subw rv64ui-p-sw \
       rv64ui-p-xor rv64ui-p-xori \
       2>/dev/null || true

  echo "Building RV64UM (Multiply/Divide) tests..."
  make rv64um-p-div rv64um-p-divu rv64um-p-divuw rv64um-p-divw \
       rv64um-p-mul rv64um-p-mulh rv64um-p-mulhsu rv64um-p-mulhu \
       rv64um-p-mulw rv64um-p-rem rv64um-p-remu rv64um-p-remuw \
       rv64um-p-remw \
       2>/dev/null || true

  echo "Building RV64UA (Atomic) tests..."
  make rv64ua-p-amoadd_d rv64ua-p-amoadd_w rv64ua-p-amoand_d rv64ua-p-amoand_w \
       rv64ua-p-amomax_d rv64ua-p-amomax_w rv64ua-p-amomaxu_d rv64ua-p-amomaxu_w \
       rv64ua-p-amomin_d rv64ua-p-amomin_w rv64ua-p-amominu_d rv64ua-p-amominu_w \
       rv64ua-p-amoor_d rv64ua-p-amoor_w rv64ua-p-amoswap_d rv64ua-p-amoswap_w \
       rv64ua-p-amoxor_d rv64ua-p-amoxor_w rv64ua-p-lrsc \
       2>/dev/null || true

  echo "Building RV64UF (Single-Precision FP) tests..."
  make rv64uf-p-fadd rv64uf-p-fclass rv64uf-p-fcmp rv64uf-p-fcvt \
       rv64uf-p-fcvt_w rv64uf-p-fdiv rv64uf-p-fmadd rv64uf-p-fmin \
       rv64uf-p-ldst rv64uf-p-move rv64uf-p-recoding \
       2>/dev/null || true

  echo "Building RV64UD (Double-Precision FP) tests..."
  make rv64ud-p-fadd rv64ud-p-fclass rv64ud-p-fcmp rv64ud-p-fcvt \
       rv64ud-p-fcvt_w rv64ud-p-fdiv rv64ud-p-fmadd rv64ud-p-fmin \
       rv64ud-p-ldst rv64ud-p-move rv64ud-p-recoding rv64ud-p-structural \
       2>/dev/null || true

  echo "Building RV64UC (Compressed Instructions) tests..."
  make rv64uc-p-rvc \
       2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="

count_tests() {
  ls $1 2>/dev/null | grep -v "\.dump$" | wc -l
}

ui32_count=$(count_tests "rv32ui-p-*")
um32_count=$(count_tests "rv32um-p-*")
ua32_count=$(count_tests "rv32ua-p-*")
uf32_count=$(count_tests "rv32uf-p-*")
ud32_count=$(count_tests "rv32ud-p-*")
uc32_count=$(count_tests "rv32uc-p-*")

echo "RV32UI (Base Integer):     $ui32_count tests"
echo "RV32UM (Multiply/Divide):  $um32_count tests"
echo "RV32UA (Atomic):           $ua32_count tests"
echo "RV32UF (Single-FP):        $uf32_count tests"
echo "RV32UD (Double-FP):        $ud32_count tests"
echo "RV32UC (Compressed):       $uc32_count tests"

total32=$((ui32_count + um32_count + ua32_count + uf32_count + ud32_count + uc32_count))
echo "RV32 Total: $total32 tests"

if [ "${BUILD_RV64:-}" = "1" ] || [ "${XLEN:-32}" = "64" ]; then
  echo ""
  ui64_count=$(count_tests "rv64ui-p-*")
  um64_count=$(count_tests "rv64um-p-*")
  ua64_count=$(count_tests "rv64ua-p-*")
  uf64_count=$(count_tests "rv64uf-p-*")
  ud64_count=$(count_tests "rv64ud-p-*")
  uc64_count=$(count_tests "rv64uc-p-*")

  echo "RV64UI (Base Integer):     $ui64_count tests"
  echo "RV64UM (Multiply/Divide):  $um64_count tests"
  echo "RV64UA (Atomic):           $ua64_count tests"
  echo "RV64UF (Single-FP):        $uf64_count tests"
  echo "RV64UD (Double-FP):        $ud64_count tests"
  echo "RV64UC (Compressed):       $uc64_count tests"

  total64=$((ui64_count + um64_count + ua64_count + uf64_count + ud64_count + uc64_count))
  echo "RV64 Total: $total64 tests"
  echo ""
  total=$((total32 + total64))
  echo "Grand Total: $total test binaries built"
else
  total=$total32
  echo "Total: $total test binaries built"
fi
echo ""

if [ $total -lt 10 ]; then
  echo "WARNING: Very few tests were built. Check for errors above."
  exit 1
fi

echo "Test binaries are in: $ISA_DIR/"
echo ""
