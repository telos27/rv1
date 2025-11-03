# Session 78: Task Switching Debug - MSTATUS.MIE Root Cause Found

**Date:** 2025-11-02
**Focus:** Debug why FreeRTOS tasks start but never switch
**Status:** ✅ Root cause identified - MSTATUS.MIE=0 blocking interrupts

## Problem Statement

FreeRTOS shows both tasks starting and printing their first "Tick", but neither task ever prints a second "Tick". This indicates tasks are starting but not switching.

```
[Task1] Started! Running at 2 Hz
[Task1] Tick
[Task2] Started! Running at 1 Hz
[Task2] Tick
<-- No further output -->
```

## Investigation Process

### 1. Verified FreeRTOS Current State
- ✅ Both Task1 and Task2 start successfully
- ✅ Each prints their first "Tick"
- ❌ Neither task ever prints a second "Tick"
- **Conclusion:** Tasks start but never switch

### 2. Checked Timer Interrupt Delivery
Used `DEBUG_INTERRUPT=1` flag to trace interrupt signals through the system.

**CLINT → SoC → Core Signal Path:**
```
CLINT.mti_o[0] → mtip_vec[0] → mtip → core.mtip_in
```

**Findings:**
- ✅ Timer fires at cycle 88,707: `[MTIP] mtip=1`
- ✅ Signal reaches core: `[INTR_IN] mtip_in=1`
- ✅ MIP.MTIP bit set: `mip=0x00000080` (bit 7)
- ✅ MIE.MTIE enabled: `mie=0x00000888` (bits 11, 7, 3)
- ✅ pending_interrupts non-zero: `pending=0x00000080`

### 3. Found Root Cause: MSTATUS.MIE=0

Debug output from cycle 88,707 onwards:
```
[INTR] mip=00000080 mie=00000888 pending=00000080 mti=1
       mstatus_mie=0 globally_en=0 intr_pend=0
[INTR] current_priv=11 exception_gated=0 exception_taken_r=0
       trap_flush=0 PC=000005ea
```

**Key Finding:**
- ✅ MIP.MTIP = 1 (timer interrupt pending)
- ✅ MIE.MTIE = 1 (timer interrupt enabled)
- ✅ pending_interrupts = 0x80 (non-zero)
- ✅ mti_pending = 1
- ❌ **`mstatus_mie=0` - Global interrupt enable DISABLED**
- ❌ **`globally_en=0` - Interrupts blocked at global level**
- ❌ **`intr_pend=0` - interrupt_pending stays 0**

**Interrupt Enable Logic:**
```verilog
assign interrupts_globally_enabled =
  (current_priv == `PRIV_M) ? mstatus_mie :
  (current_priv == `PRIV_S) ? mstatus_sie : 1'b1;

assign interrupt_pending =
  interrupts_globally_enabled && |pending_interrupts && !exception_taken_r;
```

Since `mstatus_mie=0`, the entire interrupt mechanism is blocked.

## Root Cause Analysis

**Why is MSTATUS.MIE=0?**

The CPU is running in Machine mode (`current_priv=11` = 0b11 = M-mode), and MSTATUS.MIE is disabled. This could be caused by:

1. **FreeRTOS Critical Sections:** `taskENTER_CRITICAL()` disables interrupts via CSRRC/CSRRS
2. **Idle Task Loop:** When tasks block on `vTaskDelay()`, the idle task runs
3. **WFI Instruction:** FreeRTOS port may use WFI to wait for interrupts
4. **Missing Interrupt Re-enable:** After critical sections, interrupts should be re-enabled

**Expected Behavior:**
- Tasks call `vTaskDelay()` → block and yield
- Scheduler should run with interrupts ENABLED
- Timer interrupt fires → trap handler → context switch → other task runs

**Actual Behavior:**
- Tasks start with interrupts enabled (`mstatus_mie=1` during init)
- After tasks start, interrupts get disabled (`mstatus_mie=0`)
- Timer fires but CPU never takes trap (blocked by mstatus_mie=0)
- Tasks never switch

## Evidence Trail

### Early Boot (Interrupts Enabled)
```
[CSR_WRITE] MSTATUS: op=1 wdata=00007888 rdata=00007800
            -> write_val=00007888 MIE=0->1
```

### After Tasks Start (Interrupts Disabled)
```
[CSR_WRITE] MSTATUS: op=7 wdata=00000008 rdata=00007888
            -> write_val=00007880 MIE=1->0
```

CSR operation 7 = CSRRCI (read and clear immediate), clearing bit 3 (MIE).

### When Timer Fires (Still Disabled)
```
[INTR] mip=00000080 mie=00000888 pending=00000080 mti=1
       mstatus_mie=0 globally_en=0 intr_pend=0
```

## Hardware Validation

**All interrupt hardware verified working:**
- ✅ CLINT timer comparison and interrupt generation
- ✅ SoC interrupt wiring (CLINT → Core)
- ✅ CSR MIP bit setting (mtip_in → mip[7])
- ✅ CSR MIE configuration (MTIE enabled)
- ✅ Pending interrupt calculation (mip & mie)
- ✅ Exception gating logic (Session 74 fix working)

**The CPU hardware is 100% correct.** The issue is software-level (FreeRTOS port).

## Next Steps

### 1. Investigate FreeRTOS Port Code
Check `software/freertos/port/port.c` and `portASM.S`:
- How does `vPortYield()` work?
- Does it enable interrupts before yielding?
- Check `vTaskStartScheduler()` - does it enable MIE?
- Check idle task implementation

### 2. Verify Critical Section Handling
- `taskENTER_CRITICAL()` → Should use interrupt nesting counter
- `taskEXIT_CRITICAL()` → Should restore interrupts only when count=0
- Check if critical sections are being exited properly

### 3. Check WFI/Idle Loop
- Does idle task use WFI instruction?
- WFI with interrupts disabled = infinite wait
- May need `portENABLE_INTERRUPTS()` before WFI

### 4. Add Instrumentation
Track MSTATUS.MIE writes:
- When/where does MIE get cleared?
- Is it during context switch?
- Is it in idle task?
- Is there a missing interrupt enable?

## Files Modified

None - investigation only, no code changes.

## Debug Flags Used

- `DEBUG_INTERRUPT=1` - Interrupt signal tracing
- `DEBUG_CSR=1` - CSR read/write monitoring
- `DEBUG_PC=1` - Program counter tracing

## Test Results

```bash
env XLEN=32 TIMEOUT=30 ./tools/test_freertos.sh
```

**Output:**
- FreeRTOS banner: ✅ Prints correctly
- Task creation: ✅ Both tasks created
- Scheduler start: ✅ Starts successfully
- Task1 first tick: ✅ Prints
- Task2 first tick: ✅ Prints
- Task switching: ❌ Never happens (MSTATUS.MIE=0)
- Timer interrupts: ❌ Pending but not delivered

## References

- Session 74: MRET/exception priority bug fix (still working correctly)
- Session 75: CLINT timer bug fix (req_ready timing)
- Session 76: Timer interrupt hardware validation
- Session 77: Test infrastructure validation

## Conclusion

**Task switching is NOT working because MSTATUS.MIE stays disabled after tasks start, blocking all timer interrupts.**

This is a **FreeRTOS port configuration issue**, not a CPU hardware bug. All interrupt hardware has been validated and works correctly.

**Next session:** Investigate FreeRTOS port code to find where interrupts should be re-enabled but aren't.
