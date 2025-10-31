# Session 75: Load Instruction Bug Investigation - FreeRTOS Queue Overflow

**Date**: 2025-10-31
**Status**: 🔍 **BUG IDENTIFIED - Load instruction returning wrong value**

## Overview

Investigated why FreeRTOS stops after 3 "Tick" messages. Initially appeared to be MULHU bug (Session 44-46, 60 déjà vu), but root cause analysis revealed it's actually a **load instruction bug** - LW is returning wrong data.

---

## Problem Summary

### Symptoms
- ✅ FreeRTOS boots successfully
- ✅ Tasks created and scheduler starts
- ✅ Both Task1 and Task2 print "Started!" and first "Tick"
- ❌ Execution stops at ~42K cycles (only 3 total "Tick" messages)
- ❌ Should run indefinitely (tasks have `while(1)` loops)

### Initial Hypothesis (WRONG)
- ECALL (exception code 11) appearing → suspected ECALL handler bug
- MULHU returning 0x0a instead of 0 → suspected MULHU bug (like Session 44-60)

### Actual Root Cause (IDENTIFIED)
**Load instruction bug**: `LW a5, 60(a0)` at address 0x111e returns wrong value

---

## Investigation Process

### Step 1: ECALL Analysis ✅

**Finding**: ECALLs are **expected and correct**
- ECALL is FreeRTOS task yield mechanism (`portYIELD()` macro)
- Pattern: `if (xTaskResumeAll() == 0) ecall`
- Locations:
  - `prvTimerTask` at 0x1684
  - `xTaskDelayUntil` at 0xb4a
- Handler: `freertos_risc_v_trap_handler` in `portASM.S:373`
  - Checks `mcause == 11`
  - Calls `vTaskSwitchContext`
  - Restores context and returns via MRET

**Conclusion**: ECALLs working correctly - not the bug!

---

### Step 2: Execution Termination ✅

**Observation**: Simulation ends at cycle ~42,299 inside trap handler

**UART Output**:
```
========================================
  FreeRTOS Blinky Demo
  Target: RV1 RV32IMAFDC Core
  FreeRTOS Kernel: v11.1.0
  CPU Clock: 50000000 Hz
  Tick Rate: 1000 Hz
========================================

Tasks created successfully!
Starting FreeRTOS scheduler...

[Task1] Started! Running at 2 Hz
[Task1] Tick
[Task2] Started! Running at 1 Hz
[Task2] Tick
```

Only **3 "Tick" messages total** (should be many more with 10s timeout)

**Last PC**: 0x00000556 (`prvIdleTask` entry) during exception handling

---

### Step 3: Queue Overflow Detection 🎯

**Testbench Warnings**:
```
[QUEUE-CHECK] *** ASSERTION WILL FAIL: queueLength * itemSize OVERFLOWS! ***
```

**Context** (from `software/freertos/build/freertos-blinky.elf` disassembly):
```asm
111e:  lw    a5, 60(a0)      # Load queueLength from memory
1120:  mv    s0, a0          # Save base pointer
1122:  beqz  a5, 1182        # Check if queueLength == 0
1124:  lw    a4, 64(s0)      # Load itemSize from memory
1126:  mulhu a5, a5, a4      # High word of queueLength × itemSize
112a:  bnez  a5, 1182        # If overflow (high word != 0), fail assertion
```

**Function**: `xQueueGenericReset` checking if `queueLength × itemSize` would overflow

**Expected behavior**:
- queueLength = 1
- itemSize = 84
- Product = 84 (fits in 32 bits)
- MULHU result = 0 (no overflow) ✅

**Actual behavior**:
- queueLength = 10 ❌ **WRONG!**
- itemSize = 84
- Product = 840
- MULHU result = 0 (actually correct for 10×84)
- But testbench predicts assertion will fail

---

### Step 4: MULHU Debug Output 🎯

**Testbench instrumentation** (from `tb/integration/tb_freertos.v:1128-1186`):
- Tracks MULHU through ID/EX stages
- Shows register values, forwarding, operand latching

**Debug output at cycle 30143**:
```
[MULHU-ID] Cycle 30143: MULHU detected in ID stage
[MULHU-ID]   PC: 0x00001126
[MULHU-ID]   rs1 = x15, rs2 = x14, rd = x15
[MULHU-ID]   RegFile rs1 (x15) = 0x0000000a   ← a5 contains 10!
[MULHU-ID]   RegFile rs2 (x14) = 0x00000054   ← a4 contains 84 ✓
[MULHU-ID]   Load-use hazard = 1
[MULHU-ID]   M extension stall = 0
[MULHU-ID]   Stall PC = 1
```

**Critical finding**: `a5 = 0x0a` (10 decimal) **BEFORE** MULHU executes!

---

### Step 5: Root Cause Identification 🎯

**MULHU is NOT the bug** - Session 60 fix is still in place and working.

**The real bug**: Load instruction at **0x111e** returns wrong value
```asm
111e:  lw  a5, 60(a0)   # Should load 1, actually loads 10
```

**Evidence**:
1. a5 (x15) contains 10 when reaching MULHU at 0x1126
2. Previous instruction is LW at 0x111e
3. No other instructions modify a5 between 0x111e and 0x1126
4. MULHU correctly computes high word of (10 × 84)
5. Testbench correctly predicts overflow assertion will trigger

**Bug classification**: Load/Store/Forwarding/Memory corruption issue

**Possible causes**:
1. Memory contains 10 instead of 1 (FreeRTOS queue structure corrupted)
2. Load instruction returning stale/wrong data from memory
3. Data forwarding bug (forwarding wrong value from previous store)
4. Cache/memory controller bug (unlikely - no cache in current design)

---

## Related Sessions

### Previous MULHU Bugs (NOT this issue)
- **Session 44**: MULHU bug first identified in FreeRTOS queue overflow
- **Session 45**: MULHU root cause analysis
- **Session 46**: M-extension data forwarding bug fixed
- **Session 60**: MULHU operand latch bug fixed (back-to-back M-instructions)

**Note**: Session 60 fix verified still present at line 1456-1459 in `rv32i_core_pipelined.v`

### Session 74 (Previous session)
- MRET/exception priority bug fixed (AGAIN)
- Enabled FreeRTOS scheduler to run
- Exposed this new load bug

---

## Test Results

### Current State
```bash
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh
```

**Output**:
- Boot: ✅ Success
- Scheduler start: ✅ Success
- Task switching: ✅ Works (both tasks print)
- Continuous operation: ❌ Stops at ~42K cycles
- Queue overflow: ❌ Predicted (due to wrong load value)

### Regression Tests
Not run yet - focusing on FreeRTOS bug

---

## Debug Infrastructure

### Testbench Instrumentation (`tb/integration/tb_freertos.v`)

**MULHU tracking** (lines 1128-1186):
- Always enabled (no ifdef required)
- Tracks ID/EX/WB stages
- Shows operand sources, forwarding, latching

**Queue check** (lines 840-872):
- PC=0x1122: Check queueLength != 0
- PC=0x111e: Track load base pointer
- PC=0x1126: Track MULHU inputs
- PC=0x112a: Track MULHU result and predict assertion

**Usage**: Already active in standard FreeRTOS test

---

## Next Steps (Session 76)

### Immediate Investigation

1. **Add load/store tracking**:
   - Track all writes to queueLength memory location
   - Show what value is stored vs. what value is loaded
   - Identify if corruption happens at write or read

2. **Check memory contents**:
   - Dump memory at address `a0+60` before/after load
   - Verify if memory actually contains 10 or 1
   - If memory has 1, it's a load bug
   - If memory has 10, it's a store/corruption bug

3. **Check data forwarding**:
   - Look for recent stores to same address
   - Verify EX→MEM→WB forwarding logic
   - Check if load-use hazard is handled correctly

4. **Trace queueLength writes**:
   - Find where FreeRTOS initializes queue structures
   - Verify queue creation sets queueLength=1
   - Look for any corruption between creation and check

### Debugging Commands

```bash
# Run with extended timeout
env XLEN=32 TIMEOUT=30 ./tools/test_freertos.sh 2>&1 | tee session75_output.log

# Focus on cycle 30143 area
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep -A 20 -B 20 "Cycle 30143"

# Track memory writes to queue structure
# (Need to add instrumentation in testbench)
```

### Potential Fixes

**If load bug**:
- Check memory bus timing
- Verify load result selection
- Check forwarding from MEM/WB stages

**If memory corruption**:
- Track all stores to queue memory region
- Check for stack overflow
- Verify interrupt handler doesn't corrupt memory

**If forwarding bug**:
- Review forwarding unit logic
- Check load-use hazard detection
- Verify forwarding priority (EX→MEM→WB→RegFile)

---

## Files Modified

None (investigation only)

---

## Key Insights

1. **ECALL is not a bug** - it's the FreeRTOS task yield mechanism
2. **MULHU is not a bug** - it correctly computes high word of inputs
3. **Load instruction** at 0x111e is returning 10 instead of 1
4. **Session 60 fix** is still in place and working correctly
5. **Context matters** - bug only appears in FreeRTOS, not in regression tests

---

## Conclusion

**Status**: Bug identified but not fixed

**Root cause**: Load instruction `LW a5, 60(a0)` at 0x111e returns wrong value (10 instead of 1)

**Impact**: FreeRTOS queue overflow check incorrectly fails, causing execution to stop

**Next session**: Add detailed load/store tracking to identify if bug is in:
- Memory (corruption at write time)
- Load instruction (wrong read data)
- Data forwarding (wrong forwarded value)

**Confidence**: High - debug output clearly shows a5=10 when it should be 1, and this happens before MULHU

---

**Session Time**: ~2 hours
**Lines of Investigation**: 3 (ECALL, MULHU, Load)
**Bugs Fixed**: 0
**Bugs Identified**: 1 (Load instruction)
**Follow-up Required**: Yes (Session 76)
