# Hex File Format for RV1 Simulation

## Overview

The RV1 simulator uses **Verilog `$readmemh` format** for loading program memory. This document explains the exact format required and provides tools for generating it.

## Format Specification

### Memory Organization
- Memory is organized as an array of **8-bit bytes**: `reg [7:0] mem [0:MEM_SIZE-1]`
- Memory is **little-endian** (LSB at lower address)
- Instructions are 32-bit (4 bytes) aligned on 4-byte boundaries

### Hex File Format
- **One byte per line**
- **Two hex digits** per byte (e.g., `53`, `a0`, `00`)
- **No prefix** (no `0x` or other markers)
- **No addresses** (sequential loading from address 0)
- **Lowercase or uppercase** hex digits (both work)

### Example

For the instruction `0xd0007553` (FCVT.S.W fa0, zero) at address 0x00:

```
53    <- byte 0 (bits 7:0)
75    <- byte 1 (bits 15:8)
00    <- byte 2 (bits 23:16)
d0    <- byte 3 (bits 31:24)
```

Note the **little-endian byte order**: least significant byte first.

## Generating Hex Files

### Method 1: Using `asm_to_hex.sh` (Recommended)

The simplest way to convert assembly to hex:

```bash
./tools/asm_to_hex.sh tests/asm/my_test.s
```

This creates `tests/asm/my_test.hex` automatically.

#### Options:
```bash
./tools/asm_to_hex.sh <input.s> [options]

Options:
  -march=<arch>   : RISC-V architecture (default: rv32imafc)
  -mabi=<abi>     : ABI (default: ilp32f)
  -o <output.hex> : Output hex file path
  -addr=<address> : Start address (default: 0x80000000)
```

#### Examples:
```bash
# Basic usage (F extension, start at 0x80000000)
./tools/asm_to_hex.sh tests/asm/test_fadd.s

# Base ISA only
./tools/asm_to_hex.sh tests/asm/test_simple.s -march=rv32i -mabi=ilp32

# Custom output location
./tools/asm_to_hex.sh tests/asm/fibonacci.s -o tests/vectors/fib.hex

# Different start address
./tools/asm_to_hex.sh boot.s -addr=0x00000000
```

### Method 2: Using `elf_to_hex.sh`

If you already have an ELF file:

```bash
./tools/elf_to_hex.sh my_program.elf output.hex
```

### Method 3: Manual Conversion

If you need to do it manually:

```bash
# 1. Create binary from ELF
riscv64-unknown-elf-objcopy -O binary program.elf program.bin

# 2. Convert to hex format (one byte per line)
xxd -p -c 1 program.bin > program.hex
```

## Common Pitfalls

### ❌ Wrong Format Examples

**32-bit words (WRONG)**:
```
d0007553
e0050553
```
This loads as 8-bit values: `d0`, `00`, `75`, `53`, `e0`, `05`, ...

**Space-separated bytes (WRONG for our setup)**:
```
53 75 00 d0 53 05 05 e0
```
While valid for some $readmemh uses, our scripts expect one per line.

**With prefixes (WRONG)**:
```
0x53
0x75
```
The `0x` will be interpreted as hex digits.

### ✓ Correct Format

**One byte per line**:
```
53
75
00
d0
53
05
05
e0
```

## Verifying Hex Files

### Quick Visual Check
```bash
head -20 mytest.hex
```
Should show one 2-digit hex number per line.

### Check File Size
```bash
wc -l mytest.hex
```
Number of lines = number of bytes in program.

### Compare with Disassembly
```bash
# Generate disassembly
riscv64-unknown-elf-objdump -d mytest.elf

# Compare first instruction bytes
head -4 mytest.hex
```

For instruction `0xd0007553`, should see:
```
53
75
00
d0
```

## Running Tests

After generating a hex file:

```bash
# Run with test infrastructure
./tools/test_pipelined.sh test_name

# For custom hex files, you can modify MEM_FILE
# Or use the testbench directly with iverilog -DMEM_FILE=...
```

## Debugging Memory Loading

The instruction memory prints the first 4 loaded instructions during simulation:

```
=== Instruction Memory Loaded ===
MEM_FILE: tests/asm/test.hex
First 4 instructions:
  [0x00] = 0xd0007553
  [0x04] = 0xe0050553
  [0x08] = 0xd000f5d3
  [0x0C] = 0xe00585d3
=================================
```

Compare these with your expected program to verify correct loading.

## Tools Reference

| Tool | Purpose | Input | Output |
|------|---------|-------|--------|
| `asm_to_hex.sh` | Complete assembly pipeline | `.s` file | `.hex` file |
| `elf_to_hex.sh` | ELF to hex conversion | `.elf` file | `.hex` file |
| `assemble.sh` | Legacy assembler (updated) | `.s` file | `.hex` file |

## Historical Notes

**Why This Format?**
- Verilog `$readmemh` reads space/newline-separated hex values
- Each value fills one array element
- Our memory is `reg [7:0]`, so each value is 1 byte
- One-per-line is clearest and matches official RISC-V compliance tests

**Previous Issues:**
- Early versions used `objcopy -O verilog` which produced inconsistent formats
- Some scripts generated 32-bit words instead of bytes
- Led to garbled instruction loading and many debugging sessions

**Solution:**
- Standardized on `xxd -p -c 1` for reliable byte-per-line output
- Created helper scripts with clear documentation
- All new tests should use `asm_to_hex.sh`

## See Also

- `tools/asm_to_hex.sh` - Main conversion script
- `tools/elf_to_hex.sh` - ELF conversion helper
- `rtl/memory/instruction_memory.v` - Memory module implementation
- `rtl/memory/data_memory.v` - Data memory (uses same format)
