#!/bin/bash
# elf_to_hex.sh - Convert ELF file to Verilog hex format
# Usage: elf_to_hex.sh input.elf output.hex
#
# Output format: One byte per line (hex), no prefix
# This matches the format expected by $readmemh for byte arrays

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input.elf> <output.hex>"
    echo "  Converts ELF to Verilog hex format (one byte per line)"
    exit 1
fi

INPUT_ELF="$1"
OUTPUT_HEX="$2"

if [ ! -f "$INPUT_ELF" ]; then
    echo "Error: Input file '$INPUT_ELF' not found"
    exit 1
fi

# Use riscv64-unknown-elf-objcopy if available, otherwise try riscv32
if command -v riscv64-unknown-elf-objcopy &> /dev/null; then
    OBJCOPY=riscv64-unknown-elf-objcopy
elif command -v riscv32-unknown-elf-objcopy &> /dev/null; then
    OBJCOPY=riscv32-unknown-elf-objcopy
else
    echo "Error: No RISC-V objcopy found (tried riscv64-unknown-elf-objcopy, riscv32-unknown-elf-objcopy)"
    exit 1
fi

# Create temporary binary file
TEMP_BIN=$(mktemp)
trap "rm -f $TEMP_BIN" EXIT

# Convert ELF to raw binary
$OBJCOPY -O binary "$INPUT_ELF" "$TEMP_BIN"

# Convert binary to hex format: one byte per line
# xxd -p -c 1: plain hex output, 1 byte per line
xxd -p -c 1 "$TEMP_BIN" > "$OUTPUT_HEX"

echo "Converted $INPUT_ELF to $OUTPUT_HEX ($(wc -l < $OUTPUT_HEX) bytes)"
