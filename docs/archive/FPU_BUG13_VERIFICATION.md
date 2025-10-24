# FPU Bug #13 - Root Cause VERIFIED

**Date**: 2025-10-20
**Status**: ✅ **CONFIRMED VIA DEBUG TESTING**
**Test case**: rv32uf-p-fcvt_w test #2
**Location**: `rtl/core/fp_converter.v:192, 211`

---

## Verification Summary

I've confirmed Bug #13 through detailed debug logging and mathematical analysis. The bug is in the FP→INT converter's inexact flag detection logic.

---

## Test Results

### Test Case Analyzed

**Test #2 from rv32uf-p-fcvt_w.S:**
```assembly
TEST_FP_INT_OP_S( 2,  fcvt.w.s, 0x01,         -1, -1.1, rtz);
```

**Meaning:**
- Operation: `fcvt.w.s` (convert single-precision float to signed 32-bit integer)
- Input: `-1.1`
- Expected result: `-1` (truncate to integer)
- Expected flags: `0x01` (NX=1, inexact)
- Rounding mode: RTZ (round toward zero)

### Debug Output from Converter

```
[CONVERTER] FP→INT: fp_operand=bf8ccccd, sign=1, exp=127, man=0ccccd
[CONVERTER]   is_nan=0, is_inf=0, is_zero=0
[CONVERTER]   int_exp=     0 >= 0, normal conversion
[CONVERTER]   shifted_man=0000000000000001, shift_amount=         63
[CONVERTER]   shifted_man[63:32]=00000000, shifted_man[31:0]=00000001
[CONVERTER]   Setting int_result=00000001, flag_nx=0 (shifted_man[63:32]=00000000)
```

### Mathematical Analysis

**Input FP representation (0xbf8ccccd):**
- Sign: 1 (negative)
- Exponent: 127 (biased) → unbiased = 0
- Mantissa: 0x0ccccd

**Converter calculation:**
1. `int_exp = 127 - 127 = 0`
2. Takes "normal conversion" path (int_exp >= 0)
3. `shifted_man = {1'b1, 0x0ccccd, 40'b0} >> 63`
4. Result: `shifted_man = 0x0000000000000001`

**Binary representation:**
```
Before shift: 0x8ccccd0000000000
              = 1.0001100110011001100110100000...₂ (in Q1.63 format)
              = 1.1 exactly

After >> 63:  0x0000000000000001
              = 1₂
              = integer part of 1.1
```

**The bug:**
```verilog
// Line 211 (current code):
flag_nx <= (shifted_man[63:XLEN] != 0);  // Checks bits [63:32]

// For our case:
shifted_man[63:32] = 0x00000000  → flag_nx = 0 ❌ WRONG
```

**What should happen:**
- After shifting by 63, the binary point is between bit 63 and bit 62
- Bit [63] = integer part = 1
- Bits [62:0] = fractional part = should be checked for inexact flag

**Correct check:**
```verilog
// Should check the fractional bits that were truncated:
// After >> 63, fractional bits are [62:0]
flag_nx <= (shifted_man[62:0] != 0);

// For our case:
shifted_man[62:0] = 0x0000000000000001 & 0x7FFFFFFFFFFFFFFF
                  = 0x0000000000000001 ≠ 0
                  → flag_nx = 1 ✅ CORRECT
```

---

## Root Cause Analysis

### The Conceptual Error

The code at line 211 is checking if the **upper bits** `[63:32]` are non-zero. This made sense if you're thinking "did we overflow the 32-bit result?", but that's NOT what the inexact flag means.

**Inexact flag** means: "Did we lose precision during the conversion?"

For FP→INT conversion, we lose precision when:
1. The FP value has a fractional part that gets truncated
2. The FP value is too large to represent exactly in the integer format

### Why Line 192 is Wrong

```verilog
shifted_man = {1'b1, man_fp, 40'b0} >> (63 - int_exp);
flag_nx <= (shifted_man[63:XLEN] != 0);  // Line 211
```

This logic assumes:
- Keep bits `[31:0]` as the result
- Check if bits `[63:32]` are non-zero for inexact

**But this is backwards!**

The fractional bits are the **lower** bits that get discarded, not the upper bits!

### The Correct Logic

For `int_exp >= 0`, after shifting:
- Binary point is at position `(63 - int_exp)`
- Integer bits: `[63 : (63-int_exp)]`
- Fractional bits: `[(62-int_exp) : 0]`

**Inexact flag should be:**
```verilog
// Check if we're truncating fractional bits
flag_nx <= (shifted_man[(62 - int_exp) : 0] != 0);
```

Or more simply, for the case where we keep lower 32 bits:
```verilog
// After shifting to align binary point, any non-zero bits
// BELOW the integer part indicate inexact
// For 32-bit result, this depends on int_exp

// Simpler approach: check if original had fractional part
// by checking if shifted_man has bits that don't fit in the integer portion
```

---

## Impact Verification

This bug causes test #2 to fail, which prevents the test from reaching test #5. However, my initial analysis was partially correct - test #5 ALSO has this bug for a different reason.

**Tests affected:**
- Test #2: `-1.1` → already fails here
- Test #3: `-1.0` → might pass (no fractional part)
- Test #4: `-0.9` → would fail (fractional, int_exp < 0 path)
- Test #5: `0.9` → would fail (fractional, int_exp < 0 path)

So the test actually **fails at #2, not #5** due to the bug at line 211.

However, line 177 (the `int_exp < 0` path) should work correctly for simple cases like 0.9, so perhaps there's an additional issue, or test #5 is failing for a different reason.

---

## Recommended Fix

### Option 1: Proper fractional bit detection

```verilog
else begin
  // Normal conversion: shift mantissa
  shifted_man = {1'b1, man_fp, 40'b0} >> (63 - int_exp);

  // Apply sign for signed conversions
  if (operation[0] == 1'b0 && sign_fp) begin
    int_result <= -shifted_man[XLEN-1:0];
  end else begin
    int_result <= shifted_man[XLEN-1:0];
  end

  // Set inexact flag if fractional bits were lost
  // Fractional bits are below position (63 - int_exp)
  if (int_exp < 63) begin
    // Mask for fractional bits: bits [(62-int_exp):0]
    reg [63:0] frac_mask;
    frac_mask = (64'h1 << (63 - int_exp)) - 1;
    flag_nx <= (shifted_man & frac_mask) != 0;
  end else begin
    flag_nx <= 1'b0;  // No fractional bits if exp very large
  end
end
```

### Option 2: Simpler approach

```verilog
else begin
  // Normal conversion: shift mantissa
  shifted_man = {1'b1, man_fp, 40'b0} >> (63 - int_exp);

  // Apply sign
  if (operation[0] == 1'b0 && sign_fp) begin
    int_result <= -shifted_man[XLEN-1:0];
  end else begin
    int_result <= shifted_man[XLEN-1:0];
  end

  // Inexact if lower bits (below binary point) are non-zero
  // Binary point is at bit (63-int_exp), so fractional bits are [(62-int_exp):0]
  flag_nx <= (shifted_man & ((64'h1 << (63 - int_exp)) - 1)) != 0;
end
```

---

## Next Steps

1. ✅ Bug confirmed via debug logging
2. ✅ Root cause understood
3. ⬜ Implement fix
4. ⬜ Re-test rv32uf-p-fcvt_w
5. ⬜ Run full RV32UF test suite

---

## Expected Results After Fix

**Before fix:**
- rv32uf-p-fcvt_w: FAIL at test #2 (current)
- RV32UF suite: 4/11 passing (36%)

**After fix:**
- rv32uf-p-fcvt_w: Should progress past test #2
- May reveal additional issues, but should fix the inexact flag bug
- Estimated: 6-8/11 passing (55-73%)

---

## Files Modified (Debug Session)

- `rtl/core/fp_converter.v` - Added DEBUG_FPU_CONVERTER logging
- `sim/analyze_converter_bug.py` - Analysis script
- `sim/fcvt_w_debug_full.log` - Full debug log
- `sim/test_fcvt_w_debug.vvp` - Compiled debug testbench

---

**Conclusion**: Bug #13 is 100% confirmed. The inexact flag logic at line 211 checks the wrong bit range, causing false negatives for fractional values. Fix is straightforward - check fractional bits instead of upper bits.
