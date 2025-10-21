# FPU Bug #10: Special Case Flag Contamination in FP Adder

**Date**: 2025-10-20
**Status**: ✅ FIXED
**Severity**: CRITICAL
**Impact**: Incorrect exception flags for special value operations (Inf, NaN, Zero)

---

## Summary

The FP adder was contaminating exception flags for special value operations. Specifically:
- Operations like `Inf - Inf` correctly returned NaN and set **NV (invalid)** flag
- BUT they also incorrectly set **NX (inexact)** flag due to pipeline continuation
- The ROUND stage unconditionally set `flag_nx` based on guard/round/sticky bits, even for special cases

This prevented progress beyond test #23 in the official `rv32uf-p-fadd` compliance suite.

---

## Problem Description

### Symptoms
- Test `rv32uf-p-fadd` failing at test #23
- Operation: `Inf - Inf` (invalid operation)
- **Expected flags**: NV = 1, NX = 0 (only invalid flag)
- **Actual flags**: NV = 1, NX = 1 (invalid + inexact - contamination!)

### Root Cause Analysis

The FP adder uses a 6-stage state machine:
```
IDLE → UNPACK → ALIGN → COMPUTE → NORMALIZE → ROUND → DONE
```

**Special cases** (NaN, Inf, Zero operations) are detected and handled in the **ALIGN** stage:
- Lines 175-252 in `fp_adder.v`
- They set final `result` and exception flags (`flag_nv`, `flag_nx`, etc.)
- BUT the state machine continues: `ALIGN → COMPUTE → NORMALIZE → ROUND`

In the **ROUND** stage (line 437):
```verilog
flag_nx <= guard || round || sticky;
```

This line **unconditionally overwrites** `flag_nx` for ALL operations, including special cases!
- Guard/round/sticky bits may contain garbage/stale values from previous states
- This causes flag contamination: `flag_nx` gets set even though it was explicitly cleared in ALIGN

### Example Failure

**Test #23**: `Inf - Inf` should produce NaN with only NV flag
1. **ALIGN stage**: Detects `Inf - Inf`, sets:
   - `result = 0x7FC00000` (canonical NaN) ✅
   - `flag_nv = 1` ✅
   - `flag_nx = 0` ✅
2. **COMPUTE/NORMALIZE stages**: Process with stale/garbage data
3. **ROUND stage**: Unconditionally executes:
   - `flag_nx <= guard || round || sticky`
   - If any GRS bit is 1 (from stale data), sets `flag_nx = 1` ❌
4. **Result**: NaN with **both NV and NX** flags set (incorrect!)

---

## The Fix

### Strategy

Add a `special_case_handled` flag to track when special cases are processed:
- Set to `1` in ALIGN stage when any special case is detected
- Set to `0` in UNPACK stage for new operations
- In ROUND stage, **skip flag/result updates** if `special_case_handled == 1`

This ensures special cases bypass normal computation and flag setting logic.

### Code Changes

**File**: `rtl/core/fp_adder.v`

**1. Add special case tracking flag** (line 58):
```verilog
reg special_case_handled;  // Track if special case was processed in ALIGN stage
```

**2. Initialize in reset** (line 122):
```verilog
special_case_handled <= 1'b0;
```

**3. Clear in UNPACK stage** (line 131):
```verilog
UNPACK: begin
  // Clear special case flag for new operation
  special_case_handled <= 1'b0;
  // ... rest of unpacking
end
```

**4. Set in ALIGN stage for all special cases** (lines 182, 193, 204, 215, 227, 238, 249):
```verilog
// Example: Inf - Inf case
end else if (is_inf_a && is_inf_b && (sign_a != sign_b)) begin
  result <= (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;
  flag_nv <= 1'b1;
  flag_nx <= 1'b0;  // Explicitly clear
  flag_of <= 1'b0;
  flag_uf <= 1'b0;
  special_case_handled <= 1'b1;  // ← NEW: Mark as special case
end
```

**5. Conditionally update in ROUND stage** (lines 416-440):
```verilog
ROUND: begin
  // Only process normal cases - special cases already handled in ALIGN
  if (!special_case_handled) begin
    // Apply rounding...
    // Set inexact flag (only for normal cases)
    flag_nx <= guard || round || sticky;
  end
  // else: special case - result and flags already set in ALIGN stage
end
```

### Special Cases Handled

All 7 special case branches in ALIGN stage now set `special_case_handled = 1`:
1. **NaN inputs** (is_nan_a || is_nan_b) → Return canonical NaN, NV=1
2. **Inf - Inf** (is_inf_a && is_inf_b && signs differ) → Return NaN, NV=1
3. **Inf + normal** (is_inf_a) → Return Inf, no flags
4. **Normal + Inf** (is_inf_b) → Return Inf, no flags
5. **Zero + Zero** (is_zero_a && is_zero_b) → Return ±0, no flags
6. **Zero + normal** (is_zero_a) → Return operand B, no flags
7. **Normal + zero** (is_zero_b) → Return operand A, no flags

---

## Verification

### Test Results

**Before fix**:
- `rv32uf-p-fadd`: FAILED at test #23
- RV32UF overall: 3/11 passing (27%)

**After fix**:
- `rv32uf-p-fadd`: **PASSED** ✅ (all tests passing)
- RV32UF overall: 4/11 passing (36%)

**Progress**:
- Test #23 now passing: `Inf - Inf` correctly sets only NV flag
- All subsequent tests in fadd suite also passing
- +9% overall RV32UF pass rate improvement

### Example Operations Verified

**Inf - Inf**:
- Result: `0x7FC00000` (canonical NaN) ✅
- Flags: NV=1, NX=0, OF=0, UF=0 ✅

**Inf + 5.0**:
- Result: `0x7F800000` (positive Inf) ✅
- Flags: NV=0, NX=0, OF=0, UF=0 ✅

**0.0 + 0.0**:
- Result: `0x00000000` (+0) ✅
- Flags: NV=0, NX=0, OF=0, UF=0 ✅

---

## Impact Assessment

**Severity**: CRITICAL - affected all special value additions/subtractions
**Scope**: FP_ADDER module only (similar issues may exist in other FP units)
**Tests affected**: Fixed `rv32uf-p-fadd` (test #23 onwards)
**Performance**: No performance impact, purely correctness fix
**Side effects**: None - special cases now correctly bypass normal computation

---

## Lessons Learned

1. **State machine flag hygiene**: When operations set final results early in a pipeline, they must either:
   - Skip remaining pipeline stages (modify state machine transitions), OR
   - Use a flag to prevent downstream stages from overwriting results/flags

2. **Unconditional assignments are dangerous**: Lines like `flag_nx <= guard || round || sticky;` should always be conditional on the operation type

3. **Special cases need isolation**: IEEE 754 special values (NaN, Inf, Zero) have exact results and specific flag requirements - they should be isolated from normal arithmetic paths

4. **Test-driven debugging**: The official compliance tests exposed this issue precisely at test #23, making root cause analysis straightforward

---

## Related Issues

This bug is similar to the earlier **Bug #7b** (FP Load flag contamination):
- Bug #7b: FP loads were accumulating stale flags from the pipeline
- Bug #10: FP special cases were having flags overwritten by ROUND stage
- **Common theme**: Need to prevent flag accumulation/overwrite for non-computational operations

---

## Next Steps

The test suite now shows new failures in other FP operations:
- **fcmp**: Comparison operations (likely similar flag issues)
- **fcvt**: Conversion operations (format conversion edge cases)
- **fmin**: Min/max operations (NaN handling, flag setting)
- **fdiv**: Division (timeout - likely infinite loop or very slow convergence)
- **fmadd**: Fused multiply-add (complex multi-operation flag handling)
- **recoding**: NaN-boxing and recoding verification

Each of these will require similar analysis: verify special case handling and ensure flags are set correctly per IEEE 754 requirements.

---

## Impact on Other FP Modules

**To investigate**: Do other FP modules have similar issues?

Modules to check:
- ✅ **FP_ADDER**: Fixed (this bug)
- ⚠️ **FP_MULTIPLIER**: May have special case flag contamination
- ⚠️ **FP_DIVIDER**: May have special case flag contamination
- ⚠️ **FP_FMA**: Complex 3-operation pipeline - high risk
- ⚠️ **FP_COMPARE**: May not clear flags for special comparisons
- ⚠️ **FP_MINMAX**: NaN propagation may contaminate flags

**Recommendation**: Audit all FP modules for unconditional flag assignments in pipeline stages.

---

*Fixed through systematic analysis of state machine behavior and conditional flag updates based on operation type.*
