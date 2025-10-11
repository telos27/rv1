#!/usr/bin/env python3
"""Convert ELF to hex format for instruction memory"""
import sys
import struct

if len(sys.argv) != 3:
    print("Usage: elf2hex.py <input.bin> <output.hex>")
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file, 'rb') as f:
    data = f.read()

# Pad to word boundary
if len(data) % 4 != 0:
    data += b'\x00' * (4 - len(data) % 4)

# Write as 32-bit words (little-endian)
with open(output_file, 'w') as f:
    for i in range(0, len(data), 4):
        word = struct.unpack('<I', data[i:i+4])[0]
        f.write(f'{word:08x}\n')
