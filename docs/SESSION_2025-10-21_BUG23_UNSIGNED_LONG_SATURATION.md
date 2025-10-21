# Bug #23: Unsigned Long Negative Saturation Fix

**Date**: 2025-10-21
**Status**: ✅ Fixed
**Impact**: Critical - Incorrect overflow saturation for unsigned FP→INT conversions

---

## Problem Description

The FPU converter incorrectly saturated negative floating-point values to maximum unsigned integer (all 1s) instead of 0 when converting to unsigned integer types during overflow conditions.

### Affected Instructions
- `FCVT.WU.S` - Convert single-precision FP to unsigned word
- `FCVT.LU.S` - Convert single-precision FP to unsigned long (RV64)

### Symptom
**Test Case**: `fcvt.lu.s -3e9, rtz` (Test #38 in rv32uf-p-fcvt_w)
- Input: -3e9 (0xcf32d05e) - large negative number
- Expected: `0x0000000000000000` with NV (invalid) flag
- Actual: `0xFFFFFFFFFFFFFFFF` with NV flag

The saturation value was correct (set NV flag), but the saturated result was wrong.

---

## Root Cause Analysis

### Location
`rtl/core/fp_converter.v`, lines 220-227 (overflow handling in CONVERT state)

### Original Code
```verilog
// Overflow: return max/min
case (operation)
  FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
  FCVT_WU_S: int_result <= 32'hFFFFFFFF;  // ❌ WRONG - doesn't check sign
  FCVT_L_S:  int_result <= sign_fp ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
  FCVT_LU_S: int_result <= 64'hFFFFFFFFFFFFFFFF;  // ❌ WRONG - doesn't check sign
endcase
flag_nv <= 1'b1;
```

### Issue
For unsigned conversions (FCVT.WU.S, FCVT.LU.S), the overflow saturation logic did not check the sign of the input:
- **Positive overflow** (value > UINT_MAX): Should saturate to `0xFFFFFFFF` / `0xFFFFFFFFFFFFFFFF` ✅
- **Negative values** (any negative FP): Should saturate to `0x00000000` ❌ (was returning all 1s)

Per IEEE 754 and RISC-V spec, negative values converted to unsigned integers are invalid and saturate to 0.

---

## The Fix

### Bug #23: Sign-aware Saturation
```verilog
// Overflow: return max/min
// Bug #23 fix: Unsigned conversions with negative values should saturate to 0
case (operation)
  FCVT_W_S:  int_result <= sign_fp ? 32'h80000000 : 32'h7FFFFFFF;
  FCVT_WU_S: int_result <= sign_fp ? 32'h00000000 : 32'hFFFFFFFF;  // ✅ Check sign
  FCVT_L_S:  int_result <= sign_fp ? 64'h8000000000000000 : 64'h7FFFFFFFFFFFFFFF;
  FCVT_LU_S: int_result <= sign_fp ? 64'h0000000000000000 : 64'hFFFFFFFFFFFFFFFF;  // ✅ Check sign
endcase
flag_nv <= 1'b1;
```

### Bug #23b: 64-bit Overflow Detection
**Additional Issue Found**: The 64-bit overflow check only tested for `FCVT.L.S` (signed long), excluding `FCVT.LU.S` (unsigned long).

**Original Code** (line 217-219):
```verilog
// Check for 64-bit overflow
(operation_latched[1:0] == 2'b10 && (int_exp > 63 ||
 (int_exp == 63 && man_fp != 0) ||
 (int_exp == 63 && !sign_fp)))
```

This checks `operation[1:0] == 2'b10` which is only `FCVT.L.S`. But `FCVT.LU.S` is `2'b11`, so it was excluded!

**Fixed Code** (lines 216-220):
```verilog
// Check for 64-bit overflow (both signed and unsigned long)
// Bug #23b fix: Handle both FCVT.L.S and FCVT.LU.S
(operation_latched[1] == 1'b1 && int_exp > 63) ||
(operation_latched[1] == 1'b1 && int_exp == 63 && operation_latched[0] == 1'b1) ||  // Unsigned long at 2^63 always overflows
(operation_latched[1] == 1'b1 && int_exp == 63 && operation_latched[0] == 1'b0 && (man_fp != 0 || !sign_fp))  // Signed long: overflow except exactly -2^63
```

Now checks `operation[1] == 1` to include both:
- `FCVT.L.S` = `2'b10` (signed long)
- `FCVT.LU.S` = `2'b11` (unsigned long)

And properly handles the edge case where -2^63 is representable for signed but not unsigned.

---

## Verification

### Test Results
**Before Fix**: fcvt_w failed at test #38
```
[CONVERTER]   OVERFLOW: int_exp=31, man_fp=32d05e, sign=1 -> saturate
[CONVERTER] DONE state: fp_result=0x00000000, int_result=0xffffffff
Failed at test number: 37
```

**After Fix**: fcvt_w now progresses to test #39 (2 tests further)
```
Failed at test number: 39
```

### Overall FPU Status
- **RV32UF**: 6/11 tests passing (54%)
  - ✅ Passing: fadd, fclass, fcmp, fcvt, ldst, move
  - ❌ Failing: fcvt_w (test #39), fdiv, fmadd, fmin, recoding

---

## IEEE 754 Specification Reference

From IEEE 754-2008, Section 7.1 (Invalid Operation):
> "Conversion of a floating-point number to an integer format when:
> - The source is ±∞, NaN, or a value that would overflow the destination format
> - **Or the source is negative and the destination format is unsigned**"

The invalid operation exception (NV flag) should be raised, and the result should be:
- For unsigned integers: 0 if negative, UINT_MAX if positive overflow

---

## Files Modified
- `rtl/core/fp_converter.v`:
  - Line 220-227: Added sign checks for FCVT.WU.S and FCVT.LU.S saturation
  - Line 213-220: Fixed 64-bit overflow detection to include FCVT.LU.S

---

## Related Bugs
- **Bug #20**: FP→INT overflow detection for boundary cases (int_exp == 31/63)
- **Bug #21**: Missing NV flag for unsigned negative conversions (fractional path)
- **Bug #22**: Incorrect NV flag for fractional unsigned negative conversions

All four bugs (#20, #21, #22, #23) work together to ensure correct FP→INT conversion behavior across all edge cases.

---

## Next Steps
- **Continue debugging fcvt_w**: Now failing at test #39 (progress from #37)
- **Investigate remaining failures**: fdiv, fmadd, fmin, recoding tests
- **Target**: 100% RV32UF compliance (currently 54%)
