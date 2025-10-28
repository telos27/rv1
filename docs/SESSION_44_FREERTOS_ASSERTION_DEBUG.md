# Session 44: FreeRTOS Assertion Failure - MULHU Bug Found

**Date**: 2025-10-28
**Status**: 🔍 **IN PROGRESS** - Root cause identified, fix pending
**Duration**: ~2 hours

---

## Problem Statement

FreeRTOS boots successfully but fails with an assertion immediately after starting the scheduler:

```
========================================
  FreeRTOS Blinky Demo
  Target: RV1 RV32IMAFDC Core
  FreeRTOS Kernel: v11.1.0
========================================

Tasks created successfully!
Starting FreeRTOS scheduler...

*** FATAL: Assertion failed! ***
```

---

## Investigation Summary

### Step 1: Identify Which Assertion Failed

Added instrumentation to track `vApplicationAssertionFailed()` calls:
- **Assertion PC**: 0x1cdc (vApplicationAssertionFailed entry)
- **Return address (ra)**: 0x1238
- **Calling function**: `xQueueGenericCreateStatic` → `xQueueGenericReset`

### Step 2: Narrow Down the Assertion

The assertion is in `xQueueGenericReset()` at one of two locations:
1. 0x11c8: Checks if queue pointer is NULL
2. 0x11cc: Checks if `queueLength * itemSize` overflows 32 bits

### Step 3: Capture Queue Parameters

**Queue Reset Call** (cycle 31715):
- Queue pointer: 0x8000048c ✅ (valid, not NULL)
- Reset type: 0

**Overflow Check** (cycles 31715-31771):
```c
// Code at 0x116c-0x1174:
if (queueLength == 0) assert_fail();           // 0x116c
itemSize = queue->itemSize;                     // 0x116e
upper = mulhu(queueLength, itemSize);           // 0x1170
if (upper != 0) assert_fail();                  // 0x1174
```

**Captured Values**:
- queueLength (a5) = 1 ✅
- itemSize (a4) = 84 ✅
- **MULHU result (a5) = 10 (0x0A)** ❌ **WRONG!**

**Expected**: `mulhu(1, 84)` should return 0 (since 1×84=84 fits in 32 bits)
**Actual**: Returns 10 ❌

---

## Root Cause: MULHU Returns Wrong Value

### The Bug

The `MULHU` (Multiply High Unsigned) instruction returns **10** instead of **0** when computing `1 × 84`.

**Evidence**:
```
[QUEUE-CHECK] PC=0x1170: About to execute MULHU:
[QUEUE-CHECK]   a5 (queueLength) = 1 (0x00000001)
[QUEUE-CHECK]   a4 (itemSize) = 84 (0x00000054)
[QUEUE-CHECK]   Expected product (a5*a4) = 84

[QUEUE-CHECK] PC=0x1174: mulhu result (a5) = 0x0000000a
[QUEUE-CHECK] *** ASSERTION WILL FAIL: queueLength * itemSize OVERFLOWS! ***
```

### Critical Discovery: Context-Specific Bug!

**Isolated MULHU tests PASS:**
1. ✅ Official compliance test: `rv32um-p-mulhu` **PASSES**
2. ✅ Custom test `test_mulhu_1_84` (exact same values: 1, 84) **PASSES**

**But in FreeRTOS context:**
- ❌ `MULHU 1, 84` returns 10 instead of 0

### Hypothesis

Since MULHU works correctly in isolation but fails in FreeRTOS, the bug is likely:

1. **Pipeline hazard** - Specific instruction sequence triggers forwarding bug
2. **Load-use hazard** - Previous `LW a4, 64(s0)` at 0x116e may not forward correctly to multiplier
3. **Multiplier state corruption** - Some previous operation leaves multiplier in bad state
4. **Register forwarding bug** - MULHU result being corrupted by forwarding logic

### Instruction Sequence

```asm
1168:  lw    a5, 60(a0)     # Load queueLength
116a:  mv    s0, a0         # Save queue pointer
116c:  beqz  a5, fail       # Check if queueLength == 0
116e:  lw    a4, 64(s0)     # Load itemSize ← LOAD right before MULHU!
1170:  mulhu a5, a5, a4     # Multiply (returns WRONG value!)
1174:  bnez  a5, fail       # Check if overflow
```

**Key observation**: There's a LOAD at 0x116e that feeds directly into MULHU at 0x1170. This is a classic **load-use** scenario that might expose a forwarding bug.

---

## Files Modified

1. **tb/integration/tb_freertos.v**:
   - Added assertion tracking (lines 542-605)
   - Tracks vApplicationAssertionFailed calls with return address
   - Monitors queue parameter values
   - Tracks MULHU inputs and results

2. **tests/asm/test_mulhu_1_84.s** (NEW):
   - Test MULHU with exact FreeRTOS values (1, 84)
   - **Result**: PASSES in isolation!

---

## Next Steps

### Immediate (Session 45):
1. **Add VCD waveform capture** around cycle 31715-31775
2. **Examine multiplier unit** (`rtl/core/mul_div_unit.v`):
   - Check if multiplier state is properly reset
   - Verify MULHU result selection logic
   - Look for off-by-one errors in bit selection

3. **Check forwarding paths**:
   - EX→EX forwarding for load-to-multiply
   - MEM→EX forwarding
   - WB→EX forwarding

4. **Create targeted test** that replicates the exact instruction sequence:
   ```asm
   lw   a4, 64(s0)
   mulhu a5, a5, a4
   ```

### Debug Strategy:
1. Capture waveforms for FreeRTOS run at the MULHU instruction
2. Compare with waveforms from passing `test_mulhu_1_84`
3. Find the difference in multiplier/forwarding signals
4. Fix the bug
5. Verify FreeRTOS boots past the assertion

---

## Key Insights

1. **MULHU implementation is correct** (passes official tests)
2. **Bug is context-specific** - requires particular instruction sequence
3. **Value "10" is suspicious** - not random garbage, suggests systematic error
4. **Load-use hazard likely** - LOAD immediately before MULHU

---

## Test Results

| Test | MULHU 1, 84 | Result |
|------|-------------|--------|
| Official rv32um-p-mulhu | Multiple cases | ✅ PASS |
| test_mulhu_1_84 | Exact values | ✅ PASS (returns 0) |
| FreeRTOS xQueueGenericReset | Same values | ❌ FAIL (returns 10) |

---

## Impact

**CRITICAL** - Blocks FreeRTOS from running. This is the final blocker for Phase 2 (OS Integration).

Once fixed:
- FreeRTOS scheduler will start
- Tasks will execute
- Full RTOS functionality will be available

---

## Reference

- FreeRTOS function: `xQueueGenericReset()` in `queue.c`
- Assertion macro: `configASSERT()` in `FreeRTOSConfig.h`
- Multiplier unit: `rtl/core/mul_div_unit.v`
- Test catalog: `docs/TEST_CATALOG.md`
