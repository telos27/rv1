# Bug #15: Inexact Flag Set for Exact FP→INT Conversions

**Date**: 2025-10-20
**Status**: FIXED ✅
**Impact**: fcvt_w test progressed from #7 → #17 (+10 tests passing!)

---

## Problem

The inexact flag (NX) was incorrectly set for exact floating-point to integer conversions.

**Example**: `fcvt.w.s 1.0` should produce result=1 with NO inexact flag, but was setting NX=1.

## Root Cause

Bug #13 fix introduced a logic error: it checked the **remaining bits after shift** instead of the **bits lost during shift**.

### The Flaw

```verilog
// Bug #13 fix (INCORRECT):
shifted_man = {1'b1, man_fp, 40'b0} >> (63 - int_exp);
flag_nx <= (shifted_man & ((64'h1 << (63 - int_exp)) - 1)) != 0;
```

**Problem**: For `fcvt.w.s 1.0`:
- `man_64 = 0x8000000000000000` (bit 63 = 1, rest = 0)
- Shift right by 63: `shifted_man = 0x0000000000000001`
- Check: `shifted_man & 0x7FFFFFFFFFFFFFFF` = `0x0000000000000001` ≠ 0
- **Incorrectly sets** `flag_nx = 1` ❌

Bit 0 of the shifted result IS the integer value, NOT a fractional bit!

### The Correct Approach

We must check bits that were **shifted out** (lost), not bits remaining:

```verilog
// Bug #15 fix (CORRECT):
man_64_full = {1'b1, man_fp, 40'b0};
shifted_man = man_64_full >> (63 - int_exp);

// Check bits LOST in the shift (lower (63-int_exp) bits of ORIGINAL)
lost_bits_mask = (64'h1 << (63 - int_exp)) - 1;
flag_nx <= (man_64_full & lost_bits_mask) != 0;
```

**For** `fcvt.w.s 1.0`:
- `man_64_full = 0x8000000000000000`
- `lost_bits_mask = 0x7FFFFFFFFFFFFFFF`
- `man_64_full & lost_bits_mask = 0x0000000000000000` = 0
- **Correctly sets** `flag_nx = 0` ✅

**For** `fcvt.w.s 1.1`:
- `man_64_full = 0x8CCCCD0000000000`
- `lost_bits_mask = 0x7FFFFFFFFFFFFFFF`
- `man_64_full & lost_bits_mask = 0x0CCCCD0000000000` ≠ 0
- **Correctly sets** `flag_nx = 1` ✅

---

## Fix Applied

**Location**: `rtl/core/fp_converter.v:191-237`

**Changes**:
1. Store original 64-bit mantissa in `man_64_full` before shift
2. Check bits lost during shift: `(man_64_full & lost_bits_mask) != 0`
3. Added debug logging to trace bit positions

---

## Test Results

### fcvt_w Progress

| Before Bug #15 Fix | After Bug #15 Fix |
|--------------------|-------------------|
| Failed at test #7  | Failed at test #17|
| Tests #2-#6 passing (5 tests) | Tests #2-#16 passing (15 tests!) |

**Progress**: +10 tests passing! 🎉

### Individual Test Verification

| Test | Operation     | Expected Result | Expected Flags | Status |
|------|---------------|-----------------|----------------|--------|
| #6   | fcvt.w.s 1.0  | 1               | 0x00 (none)    | ✅ PASS|
| #7   | fcvt.w.s 1.1  | 1               | 0x01 (NX)      | ✅ PASS|

---

## Files Modified

1. `rtl/core/fp_converter.v` - Lines 191-237
   - Added `man_64_full` to preserve original mantissa
   - Fixed inexact flag check to use lost bits, not remaining bits
   - Enhanced debug logging

---

## Next Steps

1. ✅ Commit Bug #15 fix
2. ⬜ Debug test #17 (fcvt.wu.s 1.1)
3. ⬜ Complete fcvt_w test suite
4. ⬜ Move to next failing RV32UF test

---

**Conclusion**: Bug #15 was a subtle logic error in the Bug #13 fix. The distinction between "bits remaining after shift" vs "bits lost during shift" is critical for correct inexact flag behavior. This fix enables 10 more tests to pass!
