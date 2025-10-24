# FPU Bug #11: FP Divider Timeout - Uninitialized Counter

**Date**: 2025-10-20
**Status**: ✅ FIXED (timeout resolved, accuracy issues remain)
**Severity**: CRITICAL
**Impact**: FP division operations causing infinite loops / timeouts

---

## Summary

The FP divider module was causing test timeouts due to an uninitialized division counter (`div_counter`). When entering the DIVIDE state, the counter value was unpredictable, causing:
- Special case checks to be skipped
- Division iterations with uninitialized registers
- Tests timing out after 49,999 cycles (vs expected ~150 cycles)

---

## Problem Description

### Symptoms
- Test `rv32uf-p-fdiv` **TIMEOUT** after 49,999 cycles
- Only 81 instructions executed (CPI = 617!)
- 99.8% of cycles were pipeline flushes
- Final PC became `0xxxxxxxxx` (undefined)

### Root Cause Analysis

The FP divider uses a 6-state FSM:
```
IDLE → UNPACK → DIVIDE → NORMALIZE → ROUND → DONE
```

**Division counter logic**:
- Line 159: `if (div_counter == DIV_CYCLES)` - Handle special cases on first iteration
- Line 235: `div_counter <= DIV_CYCLES - 1` - Initialize for normal division
- Line 245: `div_counter <= div_counter - 1` - Decrement each iteration
- Line 83: `DIVIDE: next_state = (div_counter == 0) ? NORMALIZE : DIVIDE` - Exit when done

**The bug**:
1. On reset: `div_counter <= 6'd0` (line 107)
2. On DONE: `div_counter <= DIV_CYCLES` (line 337)
3. **In UNPACK**: `div_counter` not initialized!

When entering DIVIDE state:
- If `div_counter == 0` (from reset), the check at line 159 fails
- Falls through to division iteration logic (line 231)
- But `quotient`, `remainder`, `divisor_shifted` are **uninitialized**!
- Performs garbage iterations, decrements counter
- Eventually reaches 0, exits to NORMALIZE with garbage data
- Results are wrong, tests fail

Worse - if `div_counter` has a random value != DIV_CYCLES, the divider skips special case handling entirely and performs division with uninitialized registers!

---

## The Fix

### Solution

Initialize `div_counter = DIV_CYCLES` in the **UNPACK** stage, ensuring it's always ready when DIVIDE state is entered.

### Code Changes

**File**: `rtl/core/fp_divider.v`

**Added counter initialization** (lines 146-147):
```verilog
UNPACK: begin
  // ... existing unpacking logic ...

  // Initialize division counter for next state
  div_counter <= DIV_CYCLES;

  // Clear special case flag for new operation
  special_case_handled <= 1'b0;
end
```

This ensures:
- First iteration in DIVIDE: `div_counter == DIV_CYCLES` → special cases checked ✅
- Normal division: Counter initialized to `DIV_CYCLES - 1` and counts down to 0 ✅

### Additional Fix: Special Case Flag Contamination

While fixing the timeout, also applied the same `special_case_handled` flag pattern from Bug #10:
- Added `special_case_handled` register to track special cases
- Set flag and clear all exceptions in special case branches
- This prevents flag contamination in ROUND/NORMALIZE stages

**Changes**:
- Line 57: Added `reg special_case_handled;`
- Line 108: Initialize in reset
- Line 150: Clear in UNPACK
- Lines 169, 179, 189, 199, 209, 219: Set in special case branches with explicit flag clearing

---

## Verification

### Test Results

**Before fix**:
- `rv32uf-p-fdiv`: **TIMEOUT** (49,999 cycles, 81 instructions)
- CPI: 617 (catastrophic)
- Flush cycles: 99.8%

**After fix**:
- `rv32uf-p-fdiv`: **FAILED** (but NO timeout!)
- Cycles: 146 (normal execution)
- CPI: 1.304 (healthy)
- Flush cycles: 8.2% (normal)
- Failed at test #5 (accuracy/flag issue, not timeout)

**Progress**:
- ✅ Timeout completely eliminated
- ✅ Divider now executes in reasonable time
- ⚠️ Accuracy/flag bugs remain (separate issue)

---

## Impact Assessment

**Severity**: CRITICAL - prevented any division operations from completing
**Scope**: FP_DIVIDER module only
**Tests affected**: Fixed timeout in `rv32uf-p-fdiv`
**Performance**: Reduced cycles from 49,999 → 146 (342x improvement!)

**Status**:
- Timeout bug: **FIXED** ✅
- Accuracy bugs: **OPEN** - division results still incorrect

---

## Lessons Learned

1. **Initialize all loop counters before use**: Counters must be set in the state immediately before the loop state

2. **State machine hygiene**: Don't try to override state transitions from datapath always blocks - use proper FSM structure

3. **Test metrics are diagnostic**: The CPI of 617 and 99.8% flush rate immediately indicated a stuck/looping condition

4. **Two separate always blocks can't assign same register**: The `state <= DONE` assignments in special cases conflict with the FSM update at line 75 - this is a synthesis error waiting to happen

---

## Remaining Issues

The divider still has accuracy problems:
- Test failing at test #5 (results/flags incorrect)
- Division algorithm may have bugs
- Rounding logic needs verification
- Special case handling incomplete

**Next steps**: Debug division algorithm accuracy and flag generation.

---

*Fixed through systematic state machine analysis and proper counter initialization in UNPACK stage.*
