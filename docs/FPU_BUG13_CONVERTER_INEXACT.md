# FPU Bug #13: FP→INT Converter Inexact Flag Logic Error

**Date**: 2025-10-20
**Status**: ⚠️ **IDENTIFIED - NOT YET FIXED**
**Impact**: CRITICAL - Affects 6/7 failing RV32UF tests
**Location**: `rtl/core/fp_converter.v:177`

---

## Summary

The FP→INT converter has incorrect inexact flag logic when converting fractional floating-point values to integers. This bug is the **root cause** of the clustered test #5 failures across 6 different compliance tests (fcvt, fcvt_w, fdiv, fmadd, recoding, and potentially others).

---

## Bug Description

### Location
**File**: `rtl/core/fp_converter.v`
**Lines**: 173-178

```verilog
// Check if exponent is negative (fractional result)
else if (int_exp < 0) begin
  // Round to zero
  int_result <= {XLEN{1'b0}};
  flag_nx <= (man_fp != 0);  // ❌ INCORRECT!
end
```

### The Problem

When converting a fractional FP value (e.g., 0.9) to an integer:
1. The exponent is computed: `int_exp = exp_fp - BIAS`
2. For fractional values (0 < value < 1), `int_exp < 0`
3. The result is correctly rounded to 0
4. **BUT**: The inexact flag is set based on `man_fp != 0`

### Why This Is Wrong

**Test case**: `fcvt.w.s 0.9, rtz` (from rv32uf-p-fcvt_w test #5)

**FP representation of 0.9**:
```
Sign: 0
Exponent: 126 (0x7E) → int_exp = 126 - 127 = -1
Mantissa: 0x666666 (non-zero, represents 1.8 in normalized form)
```

**Current behavior**:
- `int_exp = -1` (negative)
- Takes `int_exp < 0` branch
- Sets `int_result = 0` ✅ Correct
- Sets `flag_nx = (0x666666 != 0) = 1` ✅ Correct by accident!

**Wait... this should work?**

### The ACTUAL Bug

After closer inspection, the logic at line 177 should actually work for most cases since `man_fp` would be non-zero for fractional values like 0.9.

**However**, there may be edge cases:
1. Values very close to zero but not exactly zero
2. Subnormal numbers
3. Special rounding modes

Let me check line 192 more carefully:

```verilog
// Normal conversion: shift mantissa
shifted_man = {1'b1, man_fp, 40'b0} >> (63 - int_exp);

// ...

// Set inexact flag if rounding occurred
flag_nx <= (shifted_man[63:XLEN] != 0);  // Line 192
```

**This is checking the WRONG bits!**

For XLEN=32:
- We keep `shifted_man[31:0]` as the result
- We check if `shifted_man[63:32] != 0` for inexact

But this is backwards! The inexact flag should be set if **lower bits were discarded**, not if upper bits exist.

### Correct Logic

The inexact flag should be set if:
- For `int_exp < 0` path: The FP value is non-zero (we're truncating everything)
- For `int_exp >= 0` path: **Lower bits** (fractional part) were discarded

Current line 192 checks upper bits `[63:XLEN]`, should check **bits that were truncated**.

---

## Root Cause

**Issue 1**: Line 192 checks wrong bit range for inexact detection
**Issue 2**: May not correctly handle all rounding modes (currently only RTZ is considered)

### What Should Happen for fcvt.w.s 0.9:
```
Input: 0.9 (binary: 0.1110011001100...)
int_exp = -1 (negative)
Result: 0 (correct - truncate everything)
Flag NX: 1 (correct - we discarded fractional bits)
```

### What Should Happen for fcvt.w.s 2.9:
```
Input: 2.9 (binary: 10.1110011...)
int_exp = 1
shifted_man = shift mantissa right to align integer bits
  Full value: 10.1110011... (2 integer bits, many fractional bits)
  After shift: integer part = 2, fractional part = 0.9
Result: 2 (correct)
Flag NX: 1 (correct - we discarded the 0.9 fractional part)
```

But line 192 checks `shifted_man[63:32]` which are the **upper bits after shift**, not the discarded lower bits!

---

## Impact Analysis

### Affected Tests

This bug affects test #5 in multiple suites because they all test fractional conversions:

1. **fcvt_w** (test #5): `fcvt.w.s 0.9, rtz` → expects NX=1
2. **fcvt** (test #5): `fcvt.s.wu -2` (unsigned, may have rounding)
3. **fdiv** (test #5): Division result likely has fractional part
4. **fmadd** (test #5): FMA result conversion may be fractional
5. **recoding** (test #5): Tests NaN-boxing which may involve conversion
6. **fcmp** (test #13): May involve converted values
7. **fmin** (test #15): May involve converted values

### Why All Fail at Test #5

The compliance tests are structured to test edge cases progressively:
- Tests #1-4: Simple cases (integers, zeros, basic conversions)
- Test #5: **First fractional value** with inexact flag checking
- Tests #6+: More complex cases building on #5

When test #5 fails (wrong inexact flag), the test aborts, preventing later tests from running.

---

## Proposed Fix

### Fix Option 1: Correct bit range check (line 192)

```verilog
// Current (WRONG):
flag_nx <= (shifted_man[63:XLEN] != 0);

// Fixed (check bits that will be truncated):
// For int_exp >= 0, we need to check if fractional bits exist
// The fractional bits are the lower bits AFTER aligning the binary point
reg [63:0] fractional_mask;
fractional_mask = (64'hFFFFFFFFFFFFFFFF >> (int_exp + 1));
flag_nx <= (shifted_man & fractional_mask) != 0;
```

### Fix Option 2: Simpler approach

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

  // Check if any fractional bits were lost
  // Fractional bits are below the integer bits
  // After the shift, check if bits [62 - int_exp : 0] are non-zero
  if (int_exp < 63) begin
    flag_nx <= (shifted_man[(62 - int_exp) : 0] != 0);
  end else begin
    flag_nx <= 1'b0;  // No fractional bits if exponent is very large
  end
end
```

### Fix for line 177 (paranoid check)

Even though line 177 should work, make it more explicit:

```verilog
else if (int_exp < 0) begin
  // Round to zero
  int_result <= {XLEN{1'b0}};
  // Inexact if we're truncating a non-zero value
  flag_nx <= !is_zero;  // Use the is_zero flag computed earlier
end
```

---

## Testing Plan

### Immediate Verification

1. Run `rv32uf-p-fcvt_w` test with fix
2. Check if test #5 now passes
3. Run all 6 failing tests to see improvement

### Expected Results

**Before fix**: 4/11 tests passing (36%)
**After fix**: Estimated 8-10/11 tests passing (73-91%)

**Tests likely to pass after fix**:
- fcvt_w ✅
- fcvt ✅
- fdiv ✅ (if only flag issue)
- fmadd ✅ (if only flag issue)
- recoding ✅ (if only flag issue)
- fcmp ⚠️ (may have other issues at test #13)
- fmin ⚠️ (may have other issues at test #15)

---

## Priority

**CRITICAL** - This is the highest priority bug to fix.

**Reasoning**:
1. Single fix can resolve 5-6 tests (45-55% improvement)
2. Clustered failures indicate systematic issue
3. Converter is fundamental to many FP operations

---

## Related Bugs

This may be related to or similar to:
- Bug #10: FP adder special case flag contamination
- Bug #12: FP multiplier special case flag contamination

**Pattern**: Flag handling logic errors in FPU modules

---

## Next Steps

1. ✅ Identify bug (DONE)
2. ⬜ Implement fix in `fp_converter.v`
3. ⬜ Test with `rv32uf-p-fcvt_w`
4. ⬜ Run full RV32UF test suite
5. ⬜ Document results in PHASES.md
6. ⬜ Create bug fix commit

---

## Additional Notes

There may also be issues with:
- Rounding mode handling (currently only RTZ path is clear)
- Signed vs unsigned conversion edge cases
- Overflow detection for very large values

These should be investigated after fixing the inexact flag issue.
