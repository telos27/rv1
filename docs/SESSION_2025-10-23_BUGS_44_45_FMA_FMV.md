# Session 2025-10-23: Bugs #44 & #45 - FMA Positioning and FMV.W.X Width Mismatch

## Session Overview

**Date**: 2025-10-23 (Session 13)
**Focus**: Fix remaining RV32F test failures
**Result**: 2 bugs fixed, RV32F improved from 8/11 (72%) to 9/11 (81%)

## Bug #44: FMA ADD Stage Positioning - aligned_c Value Fix

### Problem

The `fmadd` test was failing at test #5: `(1.0 × 2.5) + 1.0`
- **Expected result**: 3.5 (0x40600000)
- **Actual result**: 4.5 (0x40900000)

### Root Cause

**File**: `rtl/core/fp_fma.v:396`

The FMA module positions the product with its leading bit at position 51, but the addend `c` has its leading bit at position 52. When aligning the addend to match the product's exponent:

```verilog
// WRONG: Preserves bit position but not VALUE
aligned_c = (man_c >> exp_diff);
```

**Example** (exp_prod=128, exp_c=127, exp_diff=1):
- `man_c` at bit 52 with exp=127 represents value 2^127
- After shift right by 1: at bit 51 with exp=128
- But bit 51 with exp=128 represents 1.0, not 0.5!
- Should be at bit 50 with exp=128 to represent 0.5

### The Fix

```verilog
// CORRECT: Shift by exp_diff+1 to preserve VALUE
aligned_c = (man_c >> (exp_diff + 1));
```

The extra +1 accounts for the fact that the product is already positioned one bit lower (at bit 51 instead of 52).

### Test Results

**Before**: rv32uf-p-fmadd FAILED at test #5
**After**: rv32uf-p-fmadd **PASSING** ✅

Test #5 now produces correct result:
- product = 0xA000000000000 (2.5)
- aligned_c = 0x4000000000000 (1.0 after shift by 2)
- sum = 0xE000000000000
- Result = 3.5 ✅

### Impact

- **Progress**: RV32F 8/11 → 9/11 (72% → 81%)
- **New passing**: fmadd test (all FMA operations: FMADD, FMSUB, FNMADD, FNMSUB)

---

## Bug #45: FMV.W.X Width Mismatch - Undefined Value Propagation

### Problem

The `move` test was timing out with bizarre symptoms:
- **Timeout**: 49,999 cycles (should be ~140)
- **Flush rate**: 99.8% (49,876 of 49,999 cycles)
- **PC**: 0xxxxxxxxx (undefined/X values)
- **Registers**: Values with X bits (e.g., a0 = 0xX2345678)
- **Test stuck**: At test #11 (gp=11), only 111 instructions executed

### Root Cause

**File**: `rtl/core/fpu.v:525`

For RV32 with FLEN=64 (RV32D configuration), the FMV.W.X instruction had:

```verilog
input wire [XLEN-1:0] int_operand,  // 32 bits for RV32
...
if (FLEN == 32) begin
  fp_result = {{(FLEN-32){1'b1}}, int_operand[31:0]};
end else begin
  fp_result = int_operand[FLEN-1:0];  // ⚠️ Accesses [63:0] of 32-bit signal!
end
```

**Problem**: When FLEN=64 but XLEN=32, the code tries to access bits [63:0] of a 32-bit signal. Bits [63:32] are undefined (X), which propagated through:

1. FMV.W.X produces FP register with X values
2. FSGNJ operates on X values → produces X output
3. FMV.X.W moves X values to integer register
4. Branch on X values → unpredictable branches → infinite flushes

### The Fix

Changed to check XLEN instead of FLEN:

```verilog
if (XLEN == 32) begin
  // RV32: int_operand is 32 bits, always NaN-box to FLEN bits
  fp_result = {{(FLEN-32){1'b1}}, int_operand[31:0]};
end else begin
  // RV64: int_operand is 64 bits
  if (FLEN == 64)
    fp_result = int_operand[63:0];
  else
    fp_result = {{32{1'b1}}, int_operand[31:0]};
end
```

For RV32D:
- Input: 32-bit integer (e.g., 0x12345678)
- Output: 64-bit NaN-boxed value (0xffffffff_12345678)

### Test Results

**Before**:
- Timeout: 49,999 cycles
- PC: 0xxxxxxxxx (X values)
- Registers: X contamination
- CPI: 450.441 (!)
- Flush rate: 99.8%

**After**:
- Completed: 138 cycles ✅
- PC: 0x8000000c (valid)
- Registers: No X values ✅
- CPI: 1.211
- Flush rate: 4.3%

The test now fails properly at test #21 (FSGNJN issue) instead of timing out.

### Impact

- **Bug fixed**: No more undefined values in move test
- **Performance**: 49,999 → 138 cycles (362× faster)
- **Revealed**: Underlying FSGNJN issue in test #21 (was hidden by timeout)

---

## Remaining Issues

### 1. fcvt_w Test Failure

**Status**: FAILED at test #5 (gp=5)
**Symptom**: Memory load returns wrong value
- Expected: a3 = 0x00000000 (loaded from memory)
- Actual: a3 = 0xffffffff

**Analysis**:
- FCVT.W.S conversion itself works correctly (0.9 → 0 ✅)
- Test loads expected value from address 0x8000203c using LW
- Memory hex file has correct data (0x00000000 at that location)
- Issue introduced during FLEN refactoring (Bug #27/#28)
- Likely related to 64-bit data_memory interface changes

**Working commit**: 7dc1afd (Bug #42)
**Broken commit**: d7c2d33 (RV32D FLEN refactoring)

### 2. move Test #21 Failure

**Status**: FAILED at test #21 (gp=0x15)
**Symptom**: FSGNJN produces wrong sign bit
- Test: `fsgnjn.s ft0, ft1, ft2` with ft1=0x12345678, ft2=0xffffffff
- Expected: a0 = 0x12345678 (sign bit = ~1 = 0)
- Actual: a0 = 0x92345678 (sign bit = 1)

**Analysis**:
- FSGNJN should copy negated sign bit: result_sign = ~sign_b
- Logic in fp_sign.v appears correct
- May be related to operand extraction or NaN-boxing after FMV.W.X fix
- Tests #1-#20 pass, only #21 fails

---

## Summary

### Bugs Fixed

1. **Bug #44**: FMA aligned_c positioning (value alignment)
2. **Bug #45**: FMV.W.X width mismatch (undefined values)

### Test Progress

| Test | Before | After | Status |
|------|--------|-------|--------|
| fmadd | FAILED | **PASSED** | ✅ Fixed |
| move | TIMEOUT | FAILED (#21) | 🔄 Partially fixed |
| fcvt_w | FAILED | FAILED | ⚠️ Needs investigation |

### Overall Progress

- **RV32F**: 8/11 (72%) → **9/11 (81%)** ✅
- **Passing**: fadd, fclass, fcmp, fcvt, fdiv, **fmadd**, fmin, ldst, recoding
- **Failing**: fcvt_w, move

### Files Modified

- `rtl/core/fp_fma.v`: Fixed aligned_c shift calculation (Bug #44)
- `rtl/core/fpu.v`: Fixed FMV.W.X width mismatch (Bug #45)

### Key Insights

1. **FMA positioning**: Must account for both bit position AND value scaling when aligning operands with different exponents
2. **Width mismatches**: When FLEN > XLEN (RV32D), must carefully handle signal width differences to avoid undefined values
3. **NaN-boxing**: RV32D requires NaN-boxing 32-bit values to 64 bits (upper 32 bits = 0xffffffff)
4. **Debugging X values**: Undefined values can cause catastrophic performance issues (99.8% flushes, 450× CPI)

### Next Steps

For next session:
1. **Priority 1**: Fix move test #21 (FSGNJN sign bit issue)
2. **Priority 2**: Debug fcvt_w memory load issue (FLEN refactoring regression)

---

## Technical Details

### FMA Alignment Math

For `(A × B) + C` where exp_prod > exp_c:

```
Product:  man_prod[52] at exp=128 → bit 51 after >>53 shift
Addend:   man_c[52] at exp=127

To align:
- Exponent difference: exp_diff = 128 - 127 = 1
- man_c needs to shift right to match product's exponent
- But product is at bit 51, man_c at bit 52
- Shift by exp_diff+1 = 2 positions: bit 52 → bit 50
- Now both represent correct values at exp=128
```

### NaN-Boxing for RV32D

Single-precision values in 64-bit FP registers must be NaN-boxed:

```
Valid:   0xffffffff_3f800000 (1.0 in lower 32, all-1s in upper 32)
Invalid: 0x00000000_3f800000 (canonical NaN)
```

RISC-V spec: "If the upper bits are not all 1s, the value is treated as a canonical NaN."

---

*Session completed 2025-10-23. Two bugs fixed, two issues remain for next session.*
