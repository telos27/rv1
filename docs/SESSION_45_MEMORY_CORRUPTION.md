# Session 45: Memory Corruption Discovery

**Date**: 2025-10-28
**Status**: 🔥 CRITICAL BUG FOUND - Memory corruption
**Impact**: BLOCKS FREERTOS - Data structures corrupted

## Root Cause Discovered

The MULHU bug is NOT a MULHU bug at all - it's **memory corruption**!

## Evidence

### Load Trace Analysis

**Load #1 - PC 0x1168 (queueLength into a5)**:
```
[LOAD-ID]   Target address = 0x800004c8
[LOAD-MEM]   mem_read_data = 0x0000000a  ← Memory has 10, should have 1!
[WB-TRACE] Cycle 31725: WB writing x15 <= 0x0000000a
```

**Load #2 - (itemSize into a4)**:
```
[WB-TRACE] Cycle 31729: WB writing x14 <= 0x00000010 ← Memory has 16, should have 84!
[WB-TRACE] *** This is the load of itemSize into a4! ***
```

### The Real Bug

Memory is corrupted:
- Address 0x800004c8 (queueLength field): Contains 10 instead of 1
- Address for itemSize field: Contains 16 instead of 84

### Why MULHU Returns 10

MULHU correctly computes:
- Input a = 0x0A (10 from corrupted queueLength)
- Input b = 0x10 (16 from corrupted itemSize)
- Product = 10 × 16 = 160 = 0xA0
- High word = 0x00...00A0 >> 32 = 0

Wait, that should return 0, not 10!

Let me re-examine... Actually from the earlier trace:
```
[MULHU-DONE]   Result = 0x0000000a
```

The result is 10 (0x0A), which matches operand_a. This suggests MULHU might be returning the WRONG output (rs1 instead of result)?

Or... let me check the actual multiplication...

## Two Distinct Issues

1. **Memory Corruption** (PRIMARY):
   - Queue structure fields have wrong values
   - queueLength = 10 instead of 1
   - itemSize = 16 instead of 84
   - Need to trace what writes these wrong values

2. **Possible MULHU Bug** (SECONDARY):
   - Even with wrong inputs (10, 16), MULHU returns 10
   - Expected: MULHU(10, 16) = high_word(160) = 0
   - Actual: 10
   - This still needs investigation

## Next Steps

1. Add memory write tracing to address 0x800004c8
2. Find what instruction writes the corrupted value (10)
3. Determine if this is a store bug or data structure initialization bug
4. Separately verify MULHU(10, 16) calculation

## Resolution: NOT Memory Corruption!

### Final Analysis

1. **FreeRTOS is correct**: Parameters 10 and 16 are THE CORRECT values
   - `configTIMER_QUEUE_LENGTH = 10` (from FreeRTOSConfig.h)
   - `sizeof(DaemonTaskMessage_t) = 16` bytes (BaseType_t + union)

2. **CPU stores correct values**: Registers a0=10, a1=16 at PC 0x122c/0x122e

3. **MULHU is WRONG**: MULHU(10, 16) returns 10 instead of 0
   - Expected: 10 × 16 = 160 = 0xA0, high word = 0
   - Actual: Returns 10 (0x0A) - INCORRECT!

4. **This matches Session 44**: Context-specific MULHU bug
   - Official rv32um-p-mulhu: PASSES ✅
   - MULHU in FreeRTOS context: FAILS ❌

## The Real Bug: MULHU Arithmetic Error

MULHU is returning the WRONG arithmetic result in certain contexts:
- Input A: 10 (0x0A)
- Input B: 16 (0x10)
- Expected output: 0 (high word of 10×16=160)
- Actual output: 10 (appears to be returning input A!)

This suggests MULHU may be bypassing the multiplication entirely and returning an input register value.
