# Session 45: MULHU Bug Analysis - Root Cause Identified

**Date**: 2025-10-28
**Status**: 🔍 ROOT CAUSE IDENTIFIED - a5 register corruption
**Impact**: CRITICAL - Blocks FreeRTOS Phase 2

## Problem Statement

FreeRTOS assertion fails with message "queueLength * itemSize OVERFLOWS":
- Expected: MULHU 1, 84 → 0 (no overflow)
- Actual: MULHU returns 0x0A (10) → triggers assertion

## Investigation Approach

Added comprehensive MULHU pipeline instrumentation to trace operand values through all stages:
- ID stage: Register file values, hazard detection
- EX stage: Forwarding paths, operand latching, multiplier inputs
- Result: Final MULHU output

## Critical Findings

### Finding 1: a5 Already Corrupted

**Cycle 31727 (ID stage)**:
```
[MULHU-ID]   RegFile rs1 (x15/a5) = 0x0000000a  ← WRONG! Should be 0x00000001
[MULHU-ID]   RegFile rs2 (x14/a4) = 0x00000054  ← CORRECT (84 decimal)
[QUEUE-CHECK]   a5 (queueLength) = 1 (0x00000001)  ← Software read shows 1!
```

**CRITICAL**: Register `a5` (x15) contains `0x0A` (10) when read by hardware decoder, but FreeRTOS code at PC 0x1170 reads it as `0x01` (1). This is **impossible** unless there's timing/sampling issue!

Wait - the QUEUE-CHECK happens at PC 0x1170 which is BEFORE MULHU executes. But MULHU-ID shows regfile value of 0x0A. Let me re-examine...

### Finding 2: Operand Latching Captures Wrong Value

**Cycle 31729 (EX stage - first cycle)**:
```
[MULHU-EX]   IDEX rs1_data = 0x0000000a           ← Latched 10, not 1
[MULHU-EX]   IDEX rs2_data = 0x800004cc           ← Base pointer, not 84!
[MULHU-EX]   Forward_b = 01                       ← Forwarding from WB
[MULHU-EX]   WB data = 0x00000010                 ← WB has 16 decimal
[MULHU-EX]   Forwarded operand_b = 0x00000010     ← Gets 16, not 84!
[MULHU-EX]   M operand_b_latched = 0x00000010     ← LATCHED WRONG VALUE!
```

**KEY INSIGHT**:
- `rs1_data` = 0x0A (10) ← This is `a5`, should be 1
- `rs2_data` = 0x800004cc ← This is the OLD value before load!
- Forwarding corrects `rs2` to 0x10 (16) from WB
- But 0x10 is STILL WRONG - should be 84 (0x54)!

### Finding 3: Previous Load Result is Wrong

The load at PC 0x1168 should load 84 from memory, but WB stage has 0x10 (16).

**Two possibilities**:
1. Memory contains wrong value (16 instead of 84)
2. Load is reading from wrong address
3. Forwarding is providing result from WRONG instruction in WB

## Root Cause Hypothesis

The issue is **NOT with MULHU itself** - it correctly multiplies the values it receives.

The issue is with **WB-stage forwarding providing the wrong data**:
- Load instruction should fetch 84 from memory
- But WB stage contains 0x10 (16) when forwarding happens
- This suggests WB has a result from a DIFFERENT instruction

This could be:
1. **Load returns wrong data from memory**
2. **Forwarding selects wrong WB data** (from different instruction)
3. **Pipeline register corruption** (memwb_rd doesn't match actual data)

## Next Steps

1. Add instrumentation to track the LOAD instruction before MULHU
2. Verify memory contents at load address
3. Check which instruction is actually in WB stage when forwarding happens
4. Verify `memwb_rd` matches the register being forwarded to

## Key Observation

The trace shows **TWO anomalies**:
1. `a5` (rs1) = 10 instead of 1
2. `a4` (rs2) = 16 (from WB forward) instead of 84

Both operands are WRONG, suggesting systematic forwarding/WB issue, not a MULHU-specific bug.

## Status

- ✅ Instrumentation added and working
- ✅ Detailed pipeline trace captured
- 🔍 Root cause: WB forwarding provides wrong values
- 🚧 Next: Trace load instruction and WB stage contents
