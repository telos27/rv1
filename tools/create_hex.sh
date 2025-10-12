#!/bin/bash
# Convert ELF to proper hex format for $readmemh
# Format: Space-separated hex bytes (2 digits each)

if [ $# -ne 2 ]; then
    echo "Usage: $0 <input.elf> <output.hex>"
    exit 1
fi

INPUT_ELF="$1"
OUTPUT_HEX="$2"

# Create temporary binary file
TEMP_BIN="/tmp/$(basename $INPUT_ELF .elf).bin"

# Convert ELF to binary
riscv64-unknown-elf-objcopy -O binary "$INPUT_ELF" "$TEMP_BIN"

# Convert binary to hex format (space-separated bytes)
# Use od to dump as hex bytes, then format for $readmemh
od -An -tx1 -v "$TEMP_BIN" | sed 's/^  *//' | sed 's/  */ /g' | tr 'a-f' 'A-F' > "$OUTPUT_HEX"

# Clean up
rm -f "$TEMP_BIN"

echo "Created hex file: $OUTPUT_HEX"
echo "Format: Space-separated hex bytes (for \$readmemh)"
