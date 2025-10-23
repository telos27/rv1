# Session 21: Bug #53 - FDIV Rounding Logic Fix - RV32D 88%!

**Date**: 2025-10-23
**Status**: ✅ COMPLETE
**RV32D Progress**: 77% → 88% (8/9 tests passing)

---

## Executive Summary

**MAJOR SUCCESS!** Fixed critical rounding bug in FP divider that was causing 1-ULP errors. The `rv32ud-p-fdiv` test now PASSES, validating all FDIV and FSQRT operations for double-precision.

**Bug #53**: FP divider rounding logic had a timing issue where the `round_up` decision was made with non-blocking assignment then immediately used in the same cycle, causing it to use stale values.

**Impact**: RV32D now at 88% (8/9 tests passing) - only `fmadd` test remains!

---

## Problem Analysis

### Test Failure

**Test**: `rv32ud-p-fdiv` failing at test #3
**Operation**: `FDIV.D` computing `-1234.0 / 1235.1`
**Expected**: `0xbfeff8b43e1929a5` (-0.9991093838555584)
**Actual**: `0xbfeff8b43e1929a4` (-0.9991093838555583)
**Error**: Off by 1 ULP (unit in last place)

### Investigation

Using DEBUG_FPU_DIVIDER flag, traced the division through all stages:

**NORMALIZE stage output**:
- Quotient bits: `0xff8b43e1929a4` (52-bit mantissa)
- Leading 1 at correct position

**ROUND stage values**:
```
Guard bit (G):  1
Round bit (R):  0
Sticky bit (S): 1
LSB bit:        1
Rounding mode:  0 (RNE - Round to Nearest, ties to Even)
```

**RNE Rounding Rule**:
```
round_up = G && (R || S || LSB)
         = 1 && (0 || 1 || 1)
         = 1 && 1
         = 1  ← Should round up!
```

But the divider produced the un-rounded result (mantissa ending in ...a4 instead of ...a5).

---

## Root Cause

Found **TWO related timing bugs** in `rtl/core/fp_divider.v`:

### Bug #53a: Non-Blocking Assignment Race Condition

**Location**: `fp_divider.v:499-529` (ROUND state)

**Problem**: The rounding decision was computed and stored with non-blocking assignment:

```verilog
ROUND: begin
  case (rounding_mode)
    3'b000: begin
      round_up <= guard && (round || sticky || lsb_bit);  // Non-blocking <=
    end
    // ...
  endcase

  // Immediately used in same cycle!
  if (round_up) begin  // ← Reading OLD value, not newly computed!
    result <= {sign_result, exp_result, quotient + 1};
  end
end
```

**Issue**: Non-blocking assignments (`<=`) don't take effect until the END of the clock cycle. When we check `if (round_up)` in the same cycle, we're reading the value from the PREVIOUS operation, not the value we just computed!

### Bug #53b: LSB Bit Corruption During Normalization

**Location**: `fp_divider.v:81-82, 441-474` (NORMALIZE state)

**Problem**: The LSB bit for tie-breaking was read dynamically from quotient:

```verilog
wire lsb_bit_div;
assign lsb_bit_div = (FLEN == 64 && !fmt_latched) ? quotient[32] : quotient[3];

// In NORMALIZE state:
quotient <= quotient << 1;  // Shift the quotient

// Later in ROUND state:
round_up = guard && (round || sticky || lsb_bit_div);  // ← Wrong bit position after shift!
```

**Issue**: When NORMALIZE shifts the quotient left by 1 or 2 bits, the LSB moves to a different position. By the time we read `lsb_bit_div` in ROUND state, it's pointing to the wrong bit!

---

## Solution

### Fix Part 1: Combinational Rounding Logic

Replaced sequential `round_up` with combinational `round_up_comb`:

```verilog
// Combinational round_up computation
reg round_up_comb;
always @(*) begin
  case (rounding_mode)
    3'b000: round_up_comb = guard && (round || sticky || lsb_bit);  // RNE
    3'b001: round_up_comb = 1'b0;                                    // RTZ
    3'b010: round_up_comb = sign_result && (guard || round || sticky);  // RDN
    3'b011: round_up_comb = !sign_result && (guard || round || sticky); // RUP
    3'b100: round_up_comb = guard;                                   // RMM
    default: round_up_comb = 1'b0;
  endcase
end

// In ROUND state:
if (round_up_comb) begin  // ← Uses freshly computed value!
  result <= {sign_result, exp_result, quotient + 1};
end
```

**Benefit**: Combinational logic computes the value in the same cycle, so it's immediately available for use.

### Fix Part 2: Latch LSB Bit Before Shifts

Added register to capture LSB bit during NORMALIZE, before any quotient shifts:

```verilog
reg lsb_bit;  // Latched LSB bit for RNE tie-breaking

// In NORMALIZE state:
if (quotient[MAN_WIDTH+3]) begin
  // Already normalized
  lsb_bit <= lsb_bit_div;  // Latch LSB BEFORE any operations
  guard <= quotient[2];
  round <= quotient[1];
  sticky <= quotient[0] || (remainder != 0);
end else if (quotient[MAN_WIDTH+2]) begin
  // Need to shift left by 1
  quotient <= quotient << 1;
  // Latch LSB from position that will become bit 3 after shift
  lsb_bit <= (FLEN == 64 && !fmt_latched) ? quotient[29] : quotient[1];
  guard <= quotient[1];
  round <= quotient[0];
  sticky <= (remainder != 0);
end
```

**Benefit**: The LSB bit is captured at the correct position and preserved through any quotient shifts.

---

## Verification

### Before Fix

```
[FDIV_ROUND] quo[bits]=0xff8b43e1929a4 g=1 r=0 s=1 lsb=1 rm=0
Computed round_up: 1 && (0 || 1 || 1) = 1  ← Correct calculation!
[FDIV_DONE] result=0xbfeff8b43e1929a4      ← But wrong result (not rounded)
```

### After Fix

```
[FDIV_ROUND] quo[bits]=0xff8b43e1929a4 g=1 r=0 s=1 lsb=1 rm=0 round_up=1
[FDIV_DONE] result=0xbfeff8b43e1929a5      ← Correct! (rounded up by 1 ULP)
```

### Test Results

**Before Bug #53 fix**:
```
rv32ud-p-fdiv...  FAILED (gp=7)
RV32D: 7/9 (77%)
```

**After Bug #53 fix**:
```
rv32ud-p-fdiv...  PASSED ✅
RV32D: 8/9 (88%)
```

**All fdiv subtests passing**:
- Test #2: `fdiv.d` with π/e ✅
- Test #3: `fdiv.d` with -1234/1235.1 ✅ (the bug fix!)
- Test #4: `fdiv.d` with π/1.0 ✅
- Test #5: `fsqrt.d` with sqrt(π) ✅
- Test #6: `fsqrt.d` with sqrt(10000) = 100 ✅
- Test #7: `fsqrt.d` with sqrt(171) ✅
- Additional tests: All passing ✅

---

## Technical Details

### IEEE 754 RNE Rounding

Round to Nearest, ties to Even (RNE) is the default IEEE 754 rounding mode:

**Rule**: Round to the nearest representable value. If exactly halfway between two values (tie), round to the one with LSB=0 (even).

**Implementation**:
```
round_up = G && (R || S || LSB)
```

Where:
- **G (Guard)**: First bit after mantissa
- **R (Round)**: Second bit after mantissa
- **S (Sticky)**: OR of all remaining bits
- **LSB**: Least significant bit of mantissa

**Cases**:
1. `G=1, R=1`: Past halfway → round up
2. `G=1, S=1`: Past halfway (some bit set beyond round) → round up
3. `G=1, R=0, S=0, LSB=1`: Exactly halfway, round to even → round up
4. `G=1, R=0, S=0, LSB=0`: Exactly halfway, already even → don't round
5. `G=0`: Below halfway → don't round

### GRS Bit Extraction

For double-precision (MAN_WIDTH=52):

**Normalized (leading 1 at bit 55)**:
- Quotient: `[55:0]` where bit 55 = leading 1 (implicit)
- Mantissa: `quotient[54:3]` (52 bits)
- Guard: `quotient[2]`
- Round: `quotient[1]`
- Sticky: `quotient[0] | (remainder != 0)`
- LSB: `quotient[3]`

**Needs 1-bit shift (leading 1 at bit 54)**:
- Before shift, latch LSB from position that will become bit 3: `quotient[1]`
- After shift: mantissa at `[54:3]`, G at `[2]`, R at `[1]`, S from remainder
- LSB: Previously latched `quotient[1]`

---

## Files Modified

1. **rtl/core/fp_divider.v**
   - Added `lsb_bit` register (line 76)
   - Added `round_up_comb` combinational logic (lines 78-88)
   - Removed `round_up` from reset initialization (line 214)
   - Added LSB latching in NORMALIZE state (lines 431, 449, 464)
   - Replaced `round_up` with `round_up_comb` in ROUND state (lines 515, 528, 541)
   - Enhanced debug output (lines 137-138)

2. **PHASES.md**
   - Updated RV32D status: 77% → 88%
   - Updated compliance table
   - Added Session 21 to project history

3. **docs/SESSION19_FCVT_TEST10_DEBUG.md**
   - Added resolution note indicating Bug #51 and #52 fixed

---

## Lessons Learned

### 1. Non-Blocking Assignment Timing

**Issue**: Using `<=` then reading in same cycle reads OLD value, not new value.

**Solution**: For values that must be used in the same cycle, use combinational logic (`always @(*)`) instead of sequential logic (`always @(posedge clk)`).

### 2. Preserving Values Through Shifts

**Issue**: Shifting registers changes bit positions, making wire-based indexing incorrect.

**Solution**: Latch critical values into registers before any shifts occur.

### 3. Debug Techniques

**Key insight**: Added debug output to show COMPUTED value vs STORED value:
```verilog
$display("Computed: %b", guard && (round || sticky || lsb_bit));  // Fresh calculation
$display("Stored: %b", round_up);  // Old value from previous cycle
```

This immediately revealed the timing mismatch.

---

## Next Session Plan

**Goal**: Fix the final RV32D test - `fmadd` (fused multiply-add)

**Status**: RV32D at 88%, only 1 test remaining!

**Approach**:
1. Run `rv32ud-p-fmadd` test with DEBUG_FPU
2. Identify which subtest is failing
3. Check FMA module for similar rounding/timing issues
4. Verify guard/round/sticky bit extraction
5. Complete RV32D 100%! 🎯

---

## Summary

**Bug #53 FIXED**: FP divider rounding now works correctly with exact IEEE 754 compliance.

**Technical Achievement**:
- Solved subtle timing bug involving non-blocking assignments
- Implemented proper LSB preservation through normalization shifts
- All FDIV and FSQRT operations now producing bit-exact results

**Progress**: RV32D 77% → 88% (8/9 tests)
**Remaining**: 1 test (fmadd) to achieve 100% RV32D compliance!

**Files Changed**: 1 RTL file (fp_divider.v)
**Lines Changed**: ~30 lines (mostly refactoring for timing correctness)

---

## Commands for Reference

```bash
# Run RV32D compliance tests
env XLEN=32 timeout 30s ./tools/run_official_tests.sh d

# Run fdiv test with divider debug
env XLEN=32 DEBUG_FPU_DIVIDER=1 timeout 10s \
  vvp sim/official-compliance/rv32ud-p-fdiv.vvp

# Check specific test results
grep "FDIV_ROUND" sim/official-compliance/rv32ud-p-fdiv.log
grep "FDIV_DONE" sim/official-compliance/rv32ud-p-fdiv.log
```

**Next**: Session 22 - Complete RV32D with fmadd fix! 🚀
