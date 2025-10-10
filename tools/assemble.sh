#!/bin/bash
# assemble.sh - Assemble RISC-V assembly file to hex format

set -e

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <assembly_file.s> [output_file.hex]"
    echo "Example: $0 tests/asm/fibonacci.s tests/vectors/fibonacci.hex"
    exit 1
fi

ASM_FILE=$1
BASE_NAME=$(basename "$ASM_FILE" .s)
DIR_NAME=$(dirname "$ASM_FILE")

# Determine output file
if [ $# -eq 2 ]; then
    HEX_FILE=$2
else
    HEX_FILE="tests/vectors/${BASE_NAME}.hex"
fi

# Temporary files
OBJ_FILE="tests/vectors/${BASE_NAME}.o"
ELF_FILE="tests/vectors/${BASE_NAME}.elf"
DUMP_FILE="tests/vectors/${BASE_NAME}.dump"

# RISC-V toolchain prefix
RISCV_PREFIX=${RISCV_PREFIX:-riscv32-unknown-elf-}

# Check if RISC-V toolchain is available
if ! command -v ${RISCV_PREFIX}as &> /dev/null; then
    echo "Error: RISC-V toolchain not found"
    echo "Please install riscv32-unknown-elf toolchain or set RISCV_PREFIX"
    exit 1
fi

# Assemble
echo "Assembling $ASM_FILE..."
${RISCV_PREFIX}as -march=rv32i -mabi=ilp32 -o "$OBJ_FILE" "$ASM_FILE"

# Link
echo "Linking..."
${RISCV_PREFIX}ld -T tests/linker.ld -o "$ELF_FILE" "$OBJ_FILE"

# Convert to hex
echo "Generating hex file..."
${RISCV_PREFIX}objcopy -O verilog "$ELF_FILE" "$HEX_FILE"

# Generate disassembly for reference
echo "Generating disassembly..."
${RISCV_PREFIX}objdump -D "$ELF_FILE" > "$DUMP_FILE"

echo "✓ Success!"
echo "  Hex file: $HEX_FILE"
echo "  Disassembly: $DUMP_FILE"

# Show first few instructions
echo ""
echo "First 10 instructions:"
${RISCV_PREFIX}objdump -d "$ELF_FILE" | head -20
