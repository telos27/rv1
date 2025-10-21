# RV1 Tools Directory

This directory contains scripts for building, testing, and debugging the RV1 RISC-V processor.

## Quick Reference

### Assembly to Hex Conversion

**Recommended: Use `asm_to_hex.sh`**
```bash
./tools/asm_to_hex.sh tests/asm/my_test.s
```

### Running Tests

```bash
./tools/test_pipelined.sh test_name
```

### Complete Workflow

```bash
# 1. Write assembly
vim tests/asm/my_test.s

# 2. Convert to hex
./tools/asm_to_hex.sh tests/asm/my_test.s

# 3. Run test
./tools/test_pipelined.sh my_test
```

## Important: Hex File Format

Hex files MUST be **one byte per line**:
```
53
75
00
d0
```

See `docs/HEX_FILE_FORMAT.md` for details.

## Tools Summary

- `asm_to_hex.sh` - Assembly to hex (recommended)
- `elf_to_hex.sh` - ELF to hex
- `test_pipelined.sh` - Run simulations
- `run_hex_tests.sh` - Run compliance tests

See docs/HEX_FILE_FORMAT.md for complete documentation.
