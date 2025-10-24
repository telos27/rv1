# FPU Converter Debugging Session - 2025-10-20

## Overview
Deep debugging session focused on fixing FPU floating-point converter bugs preventing fcvt instruction compliance.

**Starting Status**: RV32UF 4/11 tests passing (36%)
**Current Status**: RV32UF 4/11 tests passing (36%) - but major infrastructure bugs fixed
**Target**: Fix fcvt.s.w, fcvt.s.wu, fcvt.w.s, fcvt.wu.s operations

---

## Critical Bugs Fixed

### Bug #13: Leading Zero Counter Broken
**File**: `rtl/core/fp_converter.v` lines 296-365
**Symptom**: For loop incorrectly counting leading zeros
**Root Cause**: Loop incremented counter for ALL zero bits, not just leading ones before first 1
**Fix**: Replaced loop with proper `casez` priority encoder (64 cases for 64-bit values)

```verilog
// OLD (BROKEN):
for (integer i = 63; i >= 0; i = i - 1) begin
  if (int_abs[i] == 1'b0)
    leading_zeros <= leading_zeros + 1;
  else
    i = -1;  // Attempted break
end

// NEW (FIXED):
casez (int_abs_temp)
  64'b1???: lz_temp = 6'd0;
  64'b01??: lz_temp = 6'd1;
  // ... (full 64-bit priority encoder)
endcase
```

---

### Bug #13b: Mantissa Shift Off-by-One
**File**: `rtl/core/fp_converter.v` line 374
**Symptom**: Shifted mantissa by `leading_zeros + 1` instead of `leading_zeros`
**Root Cause**: Confusion about where implicit 1 bit should be positioned
**Fix**: Shift by `leading_zeros` only, extract mantissa from `[62:40]` (skipping bit 63)

```verilog
// OLD: shifted_man = int_abs << (leading_zeros + 1);
// NEW: shifted_man = int_abs_temp << lz_temp;
```

---

### Bug #14: Flag Contamination
**File**: `rtl/core/fp_converter.v` lines 135-139, 245-249
**Symptom**: Exception flags from previous operations persisted
**Root Cause**: Flags never cleared at start of new conversion
**Fix**: Clear all flags at beginning of CONVERT state

```verilog
// Added at start of both FP→INT and INT→FP paths:
flag_nv <= 1'b0;
flag_of <= 1'b0;
flag_uf <= 1'b0;
flag_nx <= 1'b0;
```

---

### Bug #16: Mantissa Rounding Overflow Not Handled
**File**: `rtl/core/fp_converter.v` lines 499-526
**Symptom**: When rounding 0x7FFFFF + 1 = 0x800000, exponent not incremented
**Root Cause**: Mantissa overflow detection missing
**Fix**: Check if mantissa is all 1s before rounding, increment exponent if overflow

```verilog
if (man_result[MAN_WIDTH-1:0] == {MAN_WIDTH{1'b1}}) begin
  // Rounding will overflow: increment exponent, set mantissa to 0
  fp_result <= {sign_result, exp_result + 1'b1, {MAN_WIDTH{1'b0}}};
end else begin
  fp_result <= {sign_result, exp_result, man_result[MAN_WIDTH-1:0] + 1'b1};
end
```

---

### Bug #17: **CRITICAL** - funct7 Direction Bit Wrong
**File**: `rtl/core/fpu.v` line 344-349
**Symptom**: ALL INT→FP conversions decoded as FP→INT!
**Root Cause**: Code checked `funct7[6]` for direction, but RISC-V spec uses `funct7[3]`

**Impact**: This bug prevented fcvt.s.w, fcvt.s.wu (INT→FP) from ever executing correctly

```verilog
// OLD (BROKEN):
// funct7[6]: direction (1=FP→INT, 0=INT→FP)  // WRONG!
assign cvt_op = (funct7[6] ? {2'b00, rs2[1:0]} : {2'b01, rs2[1:0]});

// NEW (FIXED):
// funct7[3]: direction (0=FP→INT, 1=INT→FP)  // CORRECT per RISC-V spec
assign cvt_op = (funct7[3] ? {2'b01, rs2[1:0]} : {2'b00, rs2[1:0]});
```

**Verification**:
- FCVT.W.S  (FP→INT signed):   funct7=1100000 (bit[3]=0) ✓
- FCVT.WU.S (FP→INT unsigned): funct7=1100001 (bit[3]=0) ✓
- FCVT.S.W  (INT→FP signed):   funct7=1101000 (bit[3]=1) ✓
- FCVT.S.WU (INT→FP unsigned): funct7=1101000, rs2=00001 (bit[3]=1) ✓

---

### Bug #18: **CRITICAL** - Non-blocking Assignment Timing Bug
**File**: `rtl/core/fp_converter.v` lines 268-401
**Symptom**: Converter produced undefined (X) values
**Root Cause**: Intermediate values assigned with `<=` then immediately used in same cycle

**Problem Flow**:
```verilog
// CONVERT state (same clock cycle):
int_abs <= int_operand;              // Non-blocking: won't update until next cycle
casez (int_abs) ...                  // Uses OLD value of int_abs!
shifted_man = int_abs << lz;         // Uses OLD value!
```

**Fix**: Refactored to compute ALL intermediate values with blocking `=` assignments, then register at end:

```verilog
// Compute everything combinationally first
reg [63:0] int_abs_temp;
reg [5:0] lz_temp;
reg [63:0] shifted_temp;
// ... (7 temp variables total)

int_abs_temp = int_operand;      // Blocking: available immediately
casez (int_abs_temp) ...          // Uses correct value
shifted_temp = int_abs_temp << lz_temp;

// Register at end
int_abs <= int_abs_temp;
leading_zeros <= lz_temp;
// ... (register all computed values)
```

---

## Debug Methodology

### 1. Initial Investigation
- Added comprehensive debug output to converter module
- Discovered only ONE converter call (FP→INT) in entire fcvt test
- Realized INT→FP path never executed → Bug #17

### 2. Direction Bit Analysis
```
Observed: funct7=1101000, rs2=00000, cvt_op=0000
Expected: cvt_op=0100 (FCVT_S_W = INT→FP signed)

Analysis of funct7=1101000 (0x68):
  bit[6] = 1 → OLD code thought this was FP→INT
  bit[3] = 1 → CORRECT interpretation: INT→FP
```

### 3. Timing Bug Discovery
After fixing Bug #17, converter executed but produced `0xXxxxxxxx` (undefined)
- Debug output showed 'x' values for lz_temp, exp_temp, shifted_man
- Identified non-blocking assignments creating timing hazards
- Refactored entire CONVERT state to use blocking assignments

### 4. Verification
Converter now produces correct values:
- Input: 0x00000002
- lz_temp: 62 (correct: 62 leading zeros in 64-bit 0x0000000000000002)
- exp_temp: 128 (correct: 127 + (63-62) = 128)
- fp_result: 0x40000000 (correct: 2.0 in IEEE 754)

---

## Code Changes Summary

### Files Modified
1. **rtl/core/fp_converter.v** (~150 lines changed)
   - Bug #13: Leading zero counter (casez priority encoder)
   - Bug #13b: Mantissa shift amount
   - Bug #14: Flag clearing
   - Bug #16: Rounding overflow handling
   - Bug #18: Blocking/non-blocking refactor
   - Added extensive DEBUG_FPU_CONVERTER output

2. **rtl/core/fpu.v** (~20 lines changed)
   - Bug #17: funct7[3] direction bit fix
   - Added DEBUG_FPU_CONVERTER output for cvt_op

3. **tools/run_hex_tests.sh** (~5 lines changed)
   - Added DEBUG_FPU_CONVERTER flag support

---

## Current Status

### What Works
✅ Bug #17 fixed: INT→FP conversions now routed to converter
✅ Bug #18 fixed: Converter produces defined values
✅ Test #2 (fcvt.s.w 2→2.0) converter output: 0x40000000 ✓

### Still Failing
❌ fcvt test still fails at test #5 (fcvt.s.wu -2→4.2949673e9)
❌ Only 1 conversion observed (should be 4+ for tests 2-5)
❌ Test exits after 110 cycles (early termination)

### Next Investigation Required
1. **Why only one converter call?**
   - Tests 2, 3, 4 should also call converter
   - Possible pipeline stall/flush issue?
   - Possible writeback path problem?

2. **Why does test fail before reaching test #5?**
   - Converter produced correct value for test #2
   - Need to trace where result goes after converter
   - Check FP register file writeback

3. **Converter operation encoding**
   - cvt_op=0100 observed (FCVT_S_W = INT→FP signed)
   - Test #5 needs cvt_op=0101 (FCVT_S_WU = INT→FP unsigned)
   - Verify rs2 field decoding for unsigned operations

---

## Testing Notes

### Test Environment
```bash
# Run single test with debug
DEBUG_FPU_CONVERTER=1 ./tools/run_hex_tests.sh rv32uf-p-fcvt

# Check debug output
grep "CONVERTER" sim/test_rv32uf-p-fcvt.log

# Full test suite
./tools/run_hex_tests.sh rv32uf
```

### Debug Output Interpretation
```
[FPU] FCVT operation starting:
[FPU]   funct7=1101000, rs2=00000, cvt_op=0100
[FPU]   int_operand=0x00000002, fp_operand=0x00000000

[CONVERTER] INT→FP CONVERT stage: op=0100, int_operand=0x00000002
[CONVERTER]   Positive/unsigned: int_abs = 0x00000002
[CONVERTER]   lz_temp=62, exp_temp=128 (0x80)
[CONVERTER]   shifted_temp=0x8000000000000000
[CONVERTER]   man_temp=0x0
[CONVERTER]   GRS bits: g=0, r=0, s=0

[CONVERTER] ROUND stage:
[CONVERTER]   sign=0, exp=128 (0x80), man=0x0
[CONVERTER]   No rounding: result=0x40000000

[CONVERTER] DONE state: fp_result=0x40000000, int_result=0x00000000
```

---

## Recommended Next Steps

### Immediate Priority
**INVESTIGATE WRITEBACK PATH**: Converter produces correct values but test still fails

1. Add debug output to pipeline writeback stage
2. Trace where fp_result=0x40000000 goes after DONE state
3. Verify FP register f10 receives the value
4. Check if FPU `done` signal asserts properly
5. Verify pipeline doesn't flush/stall during writeback

### Medium Priority
1. Test fcvt.w.s (FP→INT) path with debug
2. Verify Bug #16 rounding overflow logic with test case
3. Run remaining fcvt tests individually

### Lower Priority
1. Debug fcmp, fmin, fdiv, fmadd failures
2. Optimize converter performance (currently 3-cycle minimum)

---

## Technical Insights

### Verilog Synthesis Gotchas Learned
1. **Blocking vs Non-blocking**: In sequential always blocks, intermediate values used in same cycle MUST use blocking `=`
2. **For loops**: Don't synthesize as expected for priority encoding - use `casez`
3. **Variable scope**: Temporary `reg` variables can be declared inside procedural blocks
4. **Debug timing**: `$display` shows value AT THE TIME of execution, not registered values

### RISC-V Instruction Encoding
- funct7 field serves multiple purposes across different instruction types
- Always verify bit positions against official spec, not assumptions
- Conversion instructions use complex encoding with funct7 + rs2 combination

---

## Conclusion

This session fixed **6 critical bugs** (#13-#18), with two being fundamental infrastructure issues:
- **Bug #17** prevented ALL INT→FP conversions from ever working
- **Bug #18** caused all converter outputs to be undefined

The converter now **produces mathematically correct values**, but integration issues remain. The next debugging session should focus on the **writeback path** to understand why correctly computed values aren't reaching the test validation logic.

**Test Target for Next Session**: Continue with rv32uf-p-fcvt, focus on pipeline/writeback integration.
