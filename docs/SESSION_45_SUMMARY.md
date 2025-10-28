# Session 45: MULHU Bug Root Cause Analysis - Summary

**Date**: 2025-10-28
**Status**: 🔍 ROOT CAUSE IDENTIFIED - MULHU returns wrong value
**Impact**: CRITICAL - Blocks FreeRTOS Phase 2

## Executive Summary

Successfully traced the "MULHU bug" from symptom to root cause through comprehensive pipeline instrumentation. The bug is **NOT** a forwarding issue or memory corruption - it's an arithmetic error in the MULHU unit that returns operand_a (10) instead of the correct result (0) for the calculation MULHU(10, 16).

## Investigation Journey

### Phase 1: Initial Hypothesis - Forwarding Bug
- **Hypothesis**: Load-to-MUL forwarding provides wrong data
- **Approach**: Added MUL HU pipeline instrumentation (ID/EX/DONE stages)
- **Findings**: Forwarding works correctly, but result is still wrong
- **Key Insight**: MULHU receives correct operands but returns wrong result

### Phase 2: Memory Corruption Theory
- **Hypothesis**: Queue structure corrupted in memory
- **Approach**: Added memory write tracing, load instruction tracing
- **Findings**: Memory contains "wrong" values (10, 16 instead of expected 1, 84)
- **Resolution**: Values are CORRECT for FreeRTOS timer queue!
  - `configTIMER_QUEUE_LENGTH = 10` ✓
  - `sizeof(DaemonTaskMessage_t) = 16 bytes` ✓

### Phase 3: Root Cause - MULHU Arithmetic Error
- **Discovery**: MULHU(10, 16) returns 10 instead of 0
- **Verification**:
  - Input A = 10 (0x0A)
  - Input B = 16 (0x10)
  - Expected = 0 (high word of 10×16=160)
  - Actual = 10 (returns operand_a!)
- **Context**: Official rv32um-p-mulhu passes, but FreeRTOS context fails

## Root Cause Analysis

### The Bug
**MULHU returns operand_a instead of computed result**

Evidence from pipeline trace:
```
[MULHU-EX]   M operand_a_latched = 0x0000000a  (10)
[MULHU-EX]   M operand_b_latched = 0x00000010  (16)
[MULHU-DONE] Result = 0x0000000a               (10) ← WRONG! Should be 0
```

### Possible Causes

1. **Result Register Not Updated**: Multiplier completes but result not written
2. **Result Mux Error**: Wrong value selected from pipeline
3. **Timing Issue**: Result sampled before multiplier completes
4. **State Machine Bug**: Multiplier doesn't reach DONE state properly

### Why Official Tests Pass

The official `rv32um-p-mulhu` test passes, suggesting:
- Simple cases work correctly
- Bug triggered by specific pipeline state
- Possible interaction with load-use hazard or stall cycles

## Technical Details

### FreeRTOS Context
- Function: `xQueueGenericCreateStatic()` in timers.c
- PC 0x1170: `mulhu a5, a5, a4`
- Overflow check: `if (queueLength * itemSize > 32 bits) fail`
- Parameters are CORRECT: length=10, size=16
- Product = 160, fits in 32 bits → should pass
- MULHU should return 0, but returns 10 → assertion fails

### Instrumentation Added

1. **MULHU Pipeline Trace**: Tracks ID/EX/DONE stages with operand values
2. **Load Instruction Trace**: Monitors load at PC 0x1168
3. **Memory Write Trace**: Tracks stores to queue structure
4. **WB Stage Trace**: All writeback activity in critical cycles
5. **Register Trace**: Registers at store PCs

## Files Modified

- `tb/integration/tb_freertos.v`: +100 lines of debug instrumentation
- `docs/SESSION_45_MULHU_BUG_ANALYSIS.md`: Initial analysis
- `docs/SESSION_45_MEMORY_CORRUPTION.md`: Memory investigation results
- `tests/asm/test_mulhu_10_16.s`: New test case for MULHU(10, 16)

## Next Steps

1. **Add Multiplier Internal Tracing**:
   - Track `product` register in mul_unit.v
   - Monitor state machine transitions
   - Verify multiplication completes correctly

2. **Check Result Path**:
   - Trace `ex_mul_div_result` signal
   - Verify result mux selection
   - Check if result is being overwritten

3. **Create Minimal Reproduction**:
   - Build standalone test matching FreeRTOS pipeline state
   - Include load-use hazard before MULHU
   - Verify fix resolves both test and FreeRTOS

4. **Implement Fix**:
   - Once root cause confirmed, apply targeted fix
   - Run full regression (official + custom tests)
   - Verify FreeRTOS boots and runs tasks

## Key Learnings

1. **Instrumentation is Critical**: Detailed tracing revealed the real bug
2. **Don't Assume**: "Memory corruption" was actually correct data
3. **Context Matters**: Bug appears only in specific pipeline states
4. **Trust but Verify**: FreeRTOS parameters were correct all along

## Status

- ✅ Comprehensive instrumentation working
- ✅ Root cause isolated to MULHU arithmetic
- ✅ Verified inputs correct (10, 16)
- ✅ Identified wrong output (10 instead of 0)
- 🚧 Need multiplier internals trace to find exact bug
- 🚧 Need to implement and test fix

**Estimated Time to Fix**: 1-2 hours (add tracing, identify issue, implement fix, test)
