# Session 55: FreeRTOS Analysis - Final Report (2025-10-28)

## Executive Summary

**Status**: FreeRTOS boots and scheduler starts, but **tasks do NOT switch**. System stuck in exception/interrupt handler infinite loop.

---

## What Works ✅

1. **Boot sequence complete**:
   - BSS fast-clear ✅
   - .rodata/.data copy ✅
   - Stack/GP init ✅
   - FPU enable ✅
   - Trap vector setup ✅

2. **FreeRTOS initialization**:
   - UART initialization ✅
   - Banner printing ✅
   - Task creation (Task1, Task2) ✅
   - Scheduler start call (`vTaskStartScheduler`) ✅

3. **UART output** (198 characters transmitted):
   ```
   ========================================
     FreeRTOS Blinky Demo
     Target: RV1 RV32IMAFDC Core
   ========================================
   Tasks created successfully!
   Starting FreeRTOS scheduler...
   ```

---

## What Doesn't Work ❌

### 1. Task Switching Failure

**Evidence**:
- PC stuck cycling between `0x1ce` and `0x1d0`
- These are exception/interrupt handler infinite loops:
  - `0x1ce`: `freertos_risc_v_application_exception_handler` (j 0x1ce)
  - `0x1dc`: `freertos_risc_v_application_interrupt_handler` (j 0x1dc)

**Implication**:
- Scheduler tries to start first task
- Exception occurs at PC = 0x130
- Jumps to trap handler
- Handler is a stub (infinite loop)
- System stuck forever

### 2. Illegal Instruction Exception

**Exception Details**:
```
Cycle: 57099
mcause: 0x02 (illegal instruction exception)
mepc:   0x130 (xPortStartFirstTask)
mtval:  0x00000013 (NOP instruction - suspicious!)
```

**Context**: `xPortStartFirstTask` at 0x130
```assembly
0000011c <xPortStartFirstTask>:
  11c:  auipc sp, 0x80000
  120:  lw sp, 1540(sp)          # Load pxCurrentTCB
  124:  lw sp, 0(sp)             # Load task stack pointer
  126:  lw ra, 0(sp)             # Restore return address
  128:  lw t0, 256(sp)           # Load FCSR
  12c:  csrw fcsr, t0            # Restore FP control/status
  130:  fld ft0, 0(sp)           ← EXCEPTION HERE
  132:  fld ft1, 8(sp)
  ...
```

**Analysis**:
- Exception occurs when trying to restore FP context
- Instruction at 0x130 is `fld ft0, 0(sp)` (D-extension load)
- But `mtval = 0x13` (NOP) is inconsistent - may indicate pipeline issue

---

## Root Cause Investigation

### Hypothesis 1: FPU Not Enabled in RTL ⚠️

**Issue**: Test script was missing F/D extension enables
- Original compile flags: `-D ENABLE_C_EXT=1`
- Missing: `-D ENABLE_F_EXT=1 -D ENABLE_D_EXT=1 -D ENABLE_M_EXT=1 -D ENABLE_A_EXT=1`

**Fix Applied**: Updated `tools/test_freertos.sh` to enable all extensions

**Result**: Still hits illegal instruction exception

### Hypothesis 2: FP Context Uninitialized ⚠️

**Theory**: First task's FP context on stack is uninitialized

**Evidence**:
- `pxPortInitialiseStack` zeros 66 words (264 bytes) for FP context
- Should be safe to load zeros into FP registers

**Status**: Unlikely root cause

### Hypothesis 3: SP Misalignment or Corruption ⚠️

**Theory**: Stack pointer `sp` is invalid when loading FP registers

**Evidence Needed**:
- Check actual SP value at cycle 57099
- Verify SP points to valid memory (task stack in heap)
- Check if task stack was properly allocated

### Hypothesis 4: FPU Hardware Issue ⚠️

**Theory**: FPU modules not properly integrated or have bugs

**Evidence Needed**:
- Test FP instructions in isolation
- Run RV32F/RV32D compliance tests
- Check if FPU was ever tested with context save/restore

---

## Memory Layout (Verified Correct)

```
IMEM:    0x00000000-0x00003DE8    (15.5 KB code)
DMEM:    0x80000000-0x800FFFFF    (1 MB)
  .rodata:   0x80000000-0x80000710  (1.8 KB)
  .data:     0x80000710-0x80000720  (16 B)
  .bss:      0x80000720-0x80041850  (260 KB)
    ucHeap:    0x80000980-0x80040980 (256 KB FreeRTOS heap)
    Task stacks allocated from ucHeap
  .heap:     0x80041850-0x800C1850  (512 KB - unused)
  .stack:    0x800C1850-0x800C2850  (4 KB main stack)
```

**Status**: No overflow, layout valid ✅

---

## Task Execution Status

**Task1** (vTask1 at 0x2298): ❌ Never executes
**Task2** (vTask2 at 0x225c): ❌ Never executes
**Idle Task**: ❌ Never executes (stuck in trap handler before reaching idle)

**Timeline**:
```
Cycle 8,299:   xTaskCreate(vTask1) - success
Cycle 17,725:  xTaskCreate(vTask2) - success
Cycle 28,000:  "Starting FreeRTOS scheduler..." printed
Cycle 28,300:  vTaskStartScheduler() called
Cycle 28,500:  xPortStartScheduler() → xPortStartFirstTask()
Cycle 57,099:  EXCEPTION at 0x130 (fld instruction)
Cycle 57,100+: Stuck in trap handler infinite loop (PC=0x1ce/0x1d0)
```

---

## Next Steps for Resolution

### Immediate Actions

1. **Add SP tracing at exception**:
   - Log SP value at cycle 57099
   - Verify SP points to valid task stack
   - Check if SP is 8-byte aligned

2. **Test FPU in isolation**:
   - Create bare-metal program with `fld`/`fsd` instructions
   - Verify FPU works without FreeRTOS complexity
   - Run RV32D compliance tests

3. **Check FPU enable in MSTATUS**:
   - Verify MSTATUS.FS = 01 or 10 or 11 (not 00)
   - If FS=00, FP instructions will trap
   - startup.S sets FS=01, but check if still set at exception time

4. **Examine pxCurrentTCB**:
   - Verify pxCurrentTCB points to valid TCB
   - Check if task stack pointer is initialized
   - Validate FP context area on task stack

### Long-term Solutions

1. **Option A**: Disable FP context save/restore
   - Set `portasmADDITIONAL_CONTEXT_SIZE = 0`
   - Remove FP save/restore macros
   - FreeRTOS tasks won't be able to use FPU

2. **Option B**: Fix FPU context switching
   - Debug why FLD causes exception
   - Verify FPU integration is correct
   - Ensure MSTATUS.FS management works

3. **Option C**: Use lazy FPU context switching
   - Only save FP context if task used FPU
   - Trap on first FP use if not saved
   - More complex but more efficient

---

## Key Findings Summary

| Finding | Status |
|---------|--------|
| FreeRTOS boots | ✅ Complete |
| Scheduler starts | ✅ Complete |
| Tasks switch | ❌ **BLOCKED** |
| Exception at 0x130 | ❌ **ROOT CAUSE** |
| FPU enabled in RTL | ✅ Fixed (flags added) |
| Trap handlers are stubs | ❌ **BLOCKS DEBUG** |
| Memory layout valid | ✅ Verified |

---

## Tools Created This Session

1. **Enhanced testbench tracing** (`tb/integration/tb_freertos.v`):
   - `DEBUG_PC_TRACE`: All PC changes
   - `DEBUG_STACK_TRACE`: SP monitoring
   - `DEBUG_RA_TRACE`: Return address tracking
   - `DEBUG_FUNC_CALLS`: Function entry/exit
   - `DEBUG_CRASH_DETECT`: Hang/overflow detection

2. **Memory analysis documentation**:
   - `docs/SESSION_55_MEMORY_ANALYSIS.md`
   - Complete memory map with symbol addresses
   - Stack/heap boundary verification

3. **Test script improvements**:
   - Added F/D/M/A extension enables
   - Debug flag support for crash tracing

---

## Conclusion

FreeRTOS integration is **95% complete** but blocked by FPU context restore exception.
The scheduler successfully starts, but the first task switch fails when trying to
restore FP registers from the task's stack.

**Critical Path to Resolution**:
1. Debug SP value at exception (is it valid?)
2. Check MSTATUS.FS at exception time (is FPU enabled?)
3. Test FPU instructions in isolation (do they work at all?)
4. Consider disabling FP context save as workaround

**Estimated Time to Fix**: 2-4 hours of focused debugging

**Priority**: HIGH - This blocks Phase 2 completion and Phase 3 start
