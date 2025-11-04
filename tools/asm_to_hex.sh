#!/bin/bash
# asm_to_hex.sh - Complete assembly pipeline: .s -> .elf -> .hex
# Usage: asm_to_hex.sh <input.s> [options]
#
# Options:
#   -march=<arch>   : RISC-V architecture (default: rv32imafc)
#   -mabi=<abi>     : ABI (default: ilp32f)
#   -o <output.hex> : Output hex file (default: same name as input)
#   -addr=<address> : Start address (default: 0x80000000)

set -e

# Detect XLEN from environment (default to 32)
XLEN=${XLEN:-32}

# Default parameters based on XLEN
if [ "$XLEN" = "64" ]; then
    MARCH="rv64imafdc"
    MABI="lp64d"
else
    MARCH="rv32imafc"
    MABI="ilp32f"
fi

START_ADDR="0x80000000"
OUTPUT_HEX=""

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.s> [options]"
    echo "       env XLEN=64 $0 <input.s> [options]"
    echo ""
    echo "Environment:"
    echo "  XLEN=<32|64>    : Set address width (default: 32)"
    echo "                    XLEN=32 → rv32imafc/ilp32f/elf32lriscv"
    echo "                    XLEN=64 → rv64imafdcv/lp64d/elf64lriscv"
    echo ""
    echo "Options:"
    echo "  -march=<arch>   : RISC-V architecture (default: auto from XLEN)"
    echo "  -mabi=<abi>     : ABI (default: auto from XLEN)"
    echo "  -o <output.hex> : Output hex file (default: same directory as input)"
    echo "  -addr=<address> : Start address (default: 0x80000000)"
    echo ""
    echo "Examples:"
    echo "  $0 tests/asm/test.s                          # RV32"
    echo "  env XLEN=64 $0 tests/asm/test.s              # RV64"
    echo "  $0 tests/asm/test.s -march=rv32i -mabi=ilp32 # Custom arch"
    exit 1
fi

INPUT_ASM="$1"
shift

# Parse optional arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -march=*)
            MARCH="${1#-march=}"
            ;;
        -mabi=*)
            MABI="${1#-mabi=}"
            ;;
        -o)
            OUTPUT_HEX="$2"
            shift
            ;;
        -addr=*)
            START_ADDR="${1#-addr=}"
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Check input file
if [ ! -f "$INPUT_ASM" ]; then
    echo "Error: Input file '$INPUT_ASM' not found"
    exit 1
fi

# Determine output files
BASE_NAME=$(basename "$INPUT_ASM" .s)
DIR_NAME=$(dirname "$INPUT_ASM")

if [ -z "$OUTPUT_HEX" ]; then
    OUTPUT_HEX="${DIR_NAME}/${BASE_NAME}.hex"
fi

OUTPUT_O="${DIR_NAME}/${BASE_NAME}.o"
OUTPUT_ELF="${DIR_NAME}/${BASE_NAME}.elf"
OUTPUT_BIN="${DIR_NAME}/${BASE_NAME}.bin"

# RISC-V toolchain prefix
if command -v riscv64-unknown-elf-as &> /dev/null; then
    RISCV_PREFIX=riscv64-unknown-elf-
elif command -v riscv32-unknown-elf-as &> /dev/null; then
    RISCV_PREFIX=riscv32-unknown-elf-
else
    echo "Error: No RISC-V toolchain found"
    exit 1
fi

echo "========================================"
echo "RISC-V Assembly to Hex Converter"
echo "========================================"
echo "XLEN:   $XLEN-bit"
echo "Input:  $INPUT_ASM"
echo "Output: $OUTPUT_HEX"
echo "Arch:   $MARCH"
echo "ABI:    $MABI"
echo "Start:  $START_ADDR"
echo ""

# Step 1: Assemble
echo "[1/4] Assembling..."
${RISCV_PREFIX}as -march=$MARCH -mabi=$MABI "$INPUT_ASM" -o "$OUTPUT_O"

# Step 2: Link
echo "[2/4] Linking..."
if [ "$XLEN" = "64" ]; then
    ${RISCV_PREFIX}ld -m elf64lriscv --no-relax -Ttext=$START_ADDR "$OUTPUT_O" -o "$OUTPUT_ELF"
else
    ${RISCV_PREFIX}ld -m elf32lriscv --no-relax -Ttext=$START_ADDR "$OUTPUT_O" -o "$OUTPUT_ELF"
fi

# Step 3: Convert to binary
echo "[3/4] Creating binary..."
${RISCV_PREFIX}objcopy -O binary "$OUTPUT_ELF" "$OUTPUT_BIN"

# Step 4: Convert to hex (one byte per line)
echo "[4/4] Generating hex file..."
xxd -p -c 1 "$OUTPUT_BIN" > "$OUTPUT_HEX"

# Show statistics
NUM_BYTES=$(wc -l < "$OUTPUT_HEX")
NUM_INSTRS=$((NUM_BYTES / 4))

echo ""
echo "✓ Success!"
echo "  Hex file: $OUTPUT_HEX ($NUM_BYTES bytes, ~$NUM_INSTRS instructions)"

# Show disassembly
echo ""
echo "Disassembly (first 20 instructions):"
echo "----------------------------------------"
${RISCV_PREFIX}objdump -d "$OUTPUT_ELF" | head -30

# Cleanup intermediate files
rm -f "$OUTPUT_O" "$OUTPUT_BIN"

echo ""
echo "Ready to run with: ./tools/test_pipelined.sh $BASE_NAME"
