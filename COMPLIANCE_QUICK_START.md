# Official RISC-V Compliance Testing - Quick Start Guide

## TL;DR

```bash
# 1. Build all tests (one time)
./tools/build_riscv_tests.sh

# 2. Run tests
./tools/run_official_tests.sh i        # RV32I tests
./tools/run_official_tests.sh m        # M extension
./tools/run_official_tests.sh a        # A extension
./tools/run_official_tests.sh f        # F extension
./tools/run_official_tests.sh d        # D extension
./tools/run_official_tests.sh c        # C extension
./tools/run_official_tests.sh all      # All extensions
```

## What's Available

✅ **81 official RISC-V tests** ready to run:
- 42 RV32I (Base Integer)
- 8 RV32M (Multiply/Divide)
- 10 RV32A (Atomic)
- 11 RV32F (Single-Precision FP)
- 9 RV32D (Double-Precision FP)
- 1 RV32C (Compressed)

## Quick Examples

```bash
# Test one specific instruction
./tools/run_official_tests.sh i add

# Test all base integer instructions
./tools/run_official_tests.sh i

# Test multiply/divide
./tools/run_official_tests.sh m

# Run EVERYTHING
./tools/run_official_tests.sh all
```

## What You'll See

### Successful Test
```
==========================================
RV1 Official RISC-V Compliance Tests
==========================================

Testing rv32ui...

  rv32ui-p-add...                PASSED

==========================================
Test Summary
==========================================
Total:  1
Passed: 1
Failed: 0
Pass rate: 100%
```

### Failed Test
```
  rv32ui-p-add...                FAILED (gp=6)
```
(gp value indicates which test number failed)

### Timeout
```
  rv32ui-p-add...                TIMEOUT/ERROR
```
(Check `sim/official-compliance/rv32ui-p-add.log` for details)

## Where Things Are

```
riscv-tests/isa/              # Test binaries (ELF format)
tests/official-compliance/    # Converted hex files
sim/official-compliance/      # Simulation logs and results
tools/                        # Scripts
docs/OFFICIAL_COMPLIANCE_TESTING.md  # Full documentation
```

## Current Status

**Infrastructure**: ✅ Complete (100%)
**Tests Built**: ✅ 81/81 tests
**Tests Passing**: ⚠️ Debugging needed

Some tests currently timeout due to possible CSR/trap handling differences. See full documentation for debugging steps.

## Get Help

- **Full Documentation**: `docs/OFFICIAL_COMPLIANCE_TESTING.md`
- **Check logs**: `sim/official-compliance/<test>.log`
- **Enable debug**: Edit `tb/integration/tb_core_pipelined.v` line 88

## Next Steps

The infrastructure is ready! Next phase is debugging why tests hang:

1. Enable verbose PC tracing
2. Check CSR register implementation
3. Add PMP stub registers
4. Verify trap handling

See `docs/OFFICIAL_COMPLIANCE_TESTING.md` for detailed debugging guide.

---
**Created**: 2025-10-12
**Status**: Infrastructure Complete, Debugging Phase
