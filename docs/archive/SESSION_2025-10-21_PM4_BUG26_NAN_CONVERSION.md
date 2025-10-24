# Bug #26 Fix: NaN→INT Conversion Sign Bit Handling

**Date**: 2025-10-21 (PM Session 4)  
**Status**: ✅ FIXED  
**Impact**: fcvt_w test 84/85 → 85/85 (100% PASSING!)  
**RV32UF Progress**: 6/11 → 7/11 (54% → 63.6%)

---

## Summary

Fixed incorrect NaN-to-integer conversion that was checking the NaN's sign bit when it should always return the maximum positive integer value per RISC-V specification.

---

## The Bug

### Symptom
- **Test**: rv32uf-p-fcvt_w failing at test #85
- **Input**: `0xFFFFFFFF` (quiet NaN with sign bit set)
- **Operation**: FCVT.W.S (convert single-precision FP to signed 32-bit integer)
- **Expected**: `0x7FFFFFFF` (INT_MAX)
- **Actual**: `0x80000000` (INT_MIN)

### Root Cause
In `rtl/core/fp_converter.v`, lines 194-197, the NaN/Inf handling code was:

```verilog
if (is_nan || is_inf) begin
  case (operation_latched)
    FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
    //                        ^^^^^^^^ BUG: Checks sign bit for NaN
```

This incorrectly treated NaN the same as Infinity:
- For **Infinity**: Sign bit matters (+Inf→MAX, -Inf→MIN)
- For **NaN**: Sign bit is **ignored**, always→MAX (per RISC-V spec)

---

## RISC-V Specification

From the RISC-V F extension specification:

> "Output for +∞ or NaN: 2^31-1"

**Key point**: NaN conversions always return the maximum representable value, regardless of the NaN's sign bit.

### Correct Behavior

| Input      | FCVT.W.S (signed) | FCVT.WU.S (unsigned) |
|------------|-------------------|----------------------|
| +Inf       | 0x7FFFFFFF        | 0xFFFFFFFF           |
| -Inf       | 0x80000000        | 0x00000000           |
| **NaN** (any) | **0x7FFFFFFF** | **0xFFFFFFFF**       |

---

## The Fix

**File**: `rtl/core/fp_converter.v:190-200`

### Before (Incorrect)
```verilog
if (is_nan || is_inf) begin
  // Treats NaN and Inf identically
  case (operation_latched)
    FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
    FCVT_WU_S: int_result <= sign_fp ? 32'h00000000 : 32'hFFFFFFFF;
    FCVT_L_S:  int_result <= sign_fp ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
    FCVT_LU_S: int_result <= sign_fp ? 64'h0000000000000000 : 64'hFFFFFFFFFFFFFFFF;
  endcase
  flag_nv <= 1'b1;
end
```

### After (Correct)
```verilog
if (is_nan || is_inf) begin
  // Bug #26 fix: NaN always converts to maximum positive integer (per RISC-V spec)
  // Infinity respects sign bit: +Inf→max, -Inf→min (signed) or 0 (unsigned)
  case (operation_latched)
    FCVT_W_S:  int_result <= (is_nan || !sign_fp) ? 32'h7FFFFFFF : 32'h80000000;
    FCVT_WU_S: int_result <= (is_nan || !sign_fp) ? 32'hFFFFFFFF : 32'h00000000;
    FCVT_L_S:  int_result <= (is_nan || !sign_fp) ? 64'h7FFFFFFFFFFFFFFF : 64'h8000000000000000;
    FCVT_LU_S: int_result <= (is_nan || !sign_fp) ? 64'hFFFFFFFFFFFFFFFF : 64'h0000000000000000;
  endcase
  flag_nv <= 1'b1;
end
```

### Logic Breakdown

New condition: `(is_nan || !sign_fp)` evaluates to:

| is_nan | sign_fp | Result | Reason                          |
|--------|---------|--------|---------------------------------|
| 1      | X       | MAX    | NaN always→MAX                  |
| 0      | 0       | MAX    | +Inf→MAX                        |
| 0      | 1       | MIN/0  | -Inf→MIN(signed) or 0(unsigned) |

---

## Verification

### Test #85 Details
```verilog
Input:  0xFFFFFFFF (NaN: sign=1, exp=255, man=0x7FFFFF)
Operation: FCVT.W.S (FP→signed int32)
Expected: 0x7FFFFFFF (INT_MAX)
```

### Before Fix
```
[CONVERTER] FP→INT: fp_operand=00000000, sign=1, exp=255, man=7fffff
[CONVERTER]   is_nan=1, is_inf=0, is_zero=0
[CONVERTER]   NaN/Inf path: sign_fp=1, result will be set based on operation
[CONVERTER] DONE state: fp_result=0x00000000, int_result=0x80000000
Result: FAILED ✗ (Failed at test number: 85)
```

### After Fix
```
RISC-V COMPLIANCE TEST PASSED
  Test result (gp/x3): 1
  Cycles: 514
Result: PASSED ✓
```

---

## Impact

### Test Results
- **fcvt_w**: 84/85 → **85/85 (100%)** ✅
- **RV32UF**: 6/11 → **7/11 (63.6%)**

### Updated RV32UF Status
| Test      | Status | Progress |
|-----------|--------|----------|
| fadd      | ✅ PASS | 100%     |
| fclass    | ✅ PASS | 100%     |
| fcmp      | ✅ PASS | 100%     |
| fcvt      | ✅ PASS | 100%     |
| **fcvt_w**| **✅ PASS** | **100%** |
| fdiv      | ❌ FAIL | TBD      |
| fmadd     | ❌ FAIL | TBD      |
| fmin      | ❌ FAIL | TBD      |
| ldst      | ✅ PASS | 100%     |
| move      | ✅ PASS | 100%     |
| recoding  | ❌ FAIL | TBD      |

---

## Related Bugs

This is part of the ongoing FPU debugging campaign:

**Converter bugs fixed**:
- Bug #13: Leading zero counter
- Bug #13b: Mantissa shift off-by-one
- Bug #14: Flag contamination
- Bug #16: Rounding overflow
- Bug #17: Direction bit (funct7[3] vs [6])
- Bug #18: Non-blocking timing
- Bug #19: Control unit direction bit
- Bug #20: FP→INT overflow at exp==31
- Bug #21: Unsigned negative invalid flag
- Bug #22: Fractional unsigned flag refinement
- Bug #23: Unsigned long negative saturation
- Bug #24: Operation signal inconsistency
- Bug #25: Unsigned word overflow detection
- **Bug #26**: NaN→INT sign bit handling ← **THIS FIX**

**Total FPU bugs fixed**: **26 bugs**

---

## Lessons Learned

1. **NaN vs Infinity**: These special values have different conversion semantics
   - NaN: Ignores sign bit, always→maximum positive
   - Infinity: Respects sign bit for overflow saturation

2. **Debug output precision**: The debug showed `fp_operand=00000000` but that was the *current input*, not the *latched* value being processed. Always verify which signal is being displayed!

3. **RISC-V spec details matter**: The spec explicitly defines NaN behavior, and it differs from naive "check the sign bit" logic.

---

## Next Steps

**Remaining RV32UF failures** (4 tests, 36.4%):
1. **fdiv** - Division edge cases
2. **fmadd** - Fused multiply-add precision/rounding
3. **fmin** - Min/max NaN handling
4. **recoding** - NaN-boxing validation

**Recommended order**: fmin (likely similar NaN issues) → fdiv → fmadd → recoding

---

**Session Duration**: ~30 minutes  
**Key Achievement**: fcvt_w 100% complete! First perfect score on a multi-operation FPU test! 🎉
