# FPU Bug #14: FFLAGS Not Accumulating Converter Flags

**Date**: 2025-10-20
**Status**: ⚠️ **IDENTIFIED**
**Impact**: CRITICAL - Blocks fcvt_w (and likely fcvt, fcvt_w, possibly others)
**Location**: CSR file or converter integration

---

## Summary

After fixing Bug #13 (converter inexact flag logic), the converter now correctly sets `flag_nx=1` for test #2 (`fcvt.w.s -1.1`). However, when the test reads FFLAGS with `fsflags a1, x0`, it gets 0 instead of 1.

**Root cause**: Converter exception flags are not being accumulated into the FFLAGS CSR.

---

## Evidence from Execution Trace

###Test #2: `fcvt.w.s -1.1, rtz`

**Expected**:
- Result (a0): -1 (0xffffffff)
- FFLAGS (a1): 0x01 (NX bit set)

**Actual** (from trace at cycle 106):
```
[106] WB | gp=x3=2 | a0=x10=ffffffff a1=x11=00000000 a2=x12=00000001 a3=x13=ffffffff
```

- gp (x3) = 2 ✅ (test number)
- a0 (result) = 0xffffffff ✅ (correct: -1)
- **a1 (fflags) = 0x00000000 ❌ (WRONG: should be 0x01)**
- a2 (expected flags) = 0x00000001 ✅ (correct)
- a3 (expected result) = 0xffffffff ✅ (correct)

**Test comparison**:
```assembly
bne a1, a2, fail    # Compares 0x00000000 vs 0x00000001 → FAILS
```

Result: Test #2 fails on flags check, jumps to fail label (PC=0x8000058c)

---

## What We Know

1. ✅ **Converter sets flag correctly**: Debug log showed `flag_nx=1` in converter
2. ✅ **Converter completes**: Operation finished successfully
3. ❌ **FFLAGS not updated**: CSR read returns 0

---

## Hypothesis

The FP converter flags (`flag_nx`, `flag_nv`, etc.) are not being routed to the FFLAGS CSR accumulator.

Possible issues:
1. Converter flags not connected to CSR file
2. CSR file not accumulating converter flags
3. Different flag accumulation path for FP→INT vs FP→FP operations
4. Timing issue - flags written but cleared before read

---

## Next Steps

1. Check how converter flags are routed to CSR file
2. Verify FFLAGS accumulation logic includes converter operations
3. Compare with working FP operations (fadd works, so check that path)
4. Fix flag routing/accumulation

---

## Files to Check

- `rtl/core/csr_file.v` - FFLAGS accumulation logic
- `rtl/core/rv32i_core_pipelined.v` - Converter flag routing
- Compare with FP adder/multiplier flag paths (those work)

---

**Impact**: This is why fcvt_w and fcvt tests fail. Once fixed, these tests should pass immediately.
