# Session 49: Trap Handler Investigation - FreeRTOS Bus Routing Issue Found

**Date**: 2025-10-28
**Status**: 🔴 **BLOCKED** - MTIMECMP writes not reaching CLINT
**Impact**: FreeRTOS scheduler starts but tasks never run (no timer interrupts)

---

## Executive Summary

**Initial Question**: Are FreeRTOS trap handlers properly installed?

**Answer**: YES! Trap handlers are correctly installed and linked. ✅

**Real Issue Found**: FreeRTOS boots and starts the scheduler successfully, but **mtimecmp writes never reach the CLINT module**, preventing timer interrupts from firing and tasks from running.

**Root Cause**: Bus interconnect issue - store instructions to address `0x02004000` (mtimecmp) execute but don't reach CLINT peripheral.

---

## Investigation Summary

### What Works ✅

1. **Trap Handler Installation**:
   - `start.S` correctly sets mtvec to `freertos_risc_v_trap_handler` at `0x1e00`
   - `portASM.S` provides full FreeRTOS trap handler implementation
   - Handler properly linked in final ELF

2. **FreeRTOS Boot Sequence**:
   - ✅ UART initialized
   - ✅ Startup banner printed
   - ✅ Tasks created successfully (both Task1 and Task2)
   - ✅ Scheduler starts (`vTaskStartScheduler()` called)
   - ✅ `vPortSetupTimerInterrupt()` is called (confirmed in disassembly)

3. **Code Generation**:
   - GCC correctly generates address calculation for mtimecmp
   - Address `0x02004000` is computed correctly:
     ```asm
     lui   a5,0x401           # a5 = 0x00401000
     addi  a5,a5,-2048        # a5 = 0x00400800
     add   a1,mhartid,a5      # a1 = mhartid + 0x00400800
     slli  a1,a1,0x3          # a1 = (mhartid + 0x00400800) << 3 = 0x02004000 ✅
     ```

### What Doesn't Work ❌

1. **MTIMECMP Never Written**:
   - CLINT debug shows: `mtimecmp[0]=18446744073709551615` (max value, never changes)
   - No "MTIMECMP WRITE" debug messages (req_valid never true for CLINT)
   - Store instructions at PC 0x1b10 and 0x1b1e execute but don't reach CLINT

2. **No Timer Interrupts**:
   - `mti_o[0]` always 0 (never asserted)
   - Tasks never run (stuck waiting for first context switch)
   - System hangs in idle loop after scheduler starts

---

## Detailed Analysis

### FreeRTOS UART Output

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
```

Program stops here - no task output because timer interrupts never fire.

### Timer Setup Code (Disassembly)

From `xPortStartScheduler` at 0x1b30:

```asm
1b4a:  jal  1aca <vPortSetupTimerInterrupt>  # Call timer setup
1b4c:  addi s0,s0,-1920                      # Continue after return
1b50:  csrs mie,s0                            # Enable interrupts
1b54:  jal  ra,11c <xPortStartFirstTask>     # Start first task
```

From `vPortSetupTimerInterrupt` at 0x1aca:

```asm
# Calculate mtimecmp address: 0x02004000 + (mhartid * 8)
1ad4:  lui   a5,0x401
1ad8:  addi  a5,a5,-2048
1adc:  add   a1,a1,a5
1ade:  slli  a1,a1,0x3          # a1 = final address = 0x02004000

# Calculate timer value: mtime + tick_increment
1aec:  lw    a3,-4(a5)          # Read mtime_high
1af0:  lw    a2,-8(a5)          # Read mtime_low
1af4:  lw    a4,-4(a5)          # Re-read mtime_high (atomic)
1af8:  bne   a4,a3,1aec         # Retry if changed

# Add tick increment (50000 cycles for 1ms @ 50MHz)
1afc:  lui   a3,0xc
1afe:  addi  a3,a3,848          # 0xc350 = 50000
1b04:  add   a3,a3,a2           # Low word + increment
1b0a:  sltu  a0,a3,a2           # Check overflow
1b12:  add   a7,a0,a4           # High word + carry

# Write mtimecmp (TWO 32-bit stores)
1b10:  sw    a3,0(a1)           # Write mtimecmp[31:0]   ❌ Never reaches CLINT
1b1e:  sw    a7,4(a1)           # Write mtimecmp[63:32]  ❌ Never reaches CLINT
```

### Address Decoding Verification

CLINT address range check:
```
Address:     0x02004000
CLINT_BASE:  0x02000000
CLINT_MASK:  0xFFFF0000
Match: (0x02004000 & 0xFFFF0000) == 0x02000000  ✅ Should route to CLINT
```

CLINT supports 32-bit writes:
- Line 163-168 in `clint.v` handle 32-bit writes to mtimecmp
- Two consecutive 32-bit stores should work correctly

### Configuration Values

From `FreeRTOSConfig.h`:
```c
#define configMTIME_BASE_ADDRESS        (0x0200BFF8UL)  // MTIME counter
#define configMTIMECMP_BASE_ADDRESS     (0x02004000UL)  // MTIMECMP for hart 0
#define configCPU_CLOCK_HZ              (50000000)      // 50 MHz
#define configTICK_RATE_HZ              (1000)          // 1 ms tick
```

Expected tick increment: `50000000 / 1000 = 50000 cycles = 0xC350` ✅

---

## Key Insights

### Initial Confusion About "Trap Handler Stubs"

The Session 48 notes mentioned "trap handlers are infinite loop stubs at 0x1c2/0x1d0". This was MISLEADING:

**Clarification**:
- `0x1e00`: **Main trap handler** - `freertos_risc_v_trap_handler` (CORRECT, fully implemented)
- `0x1c2`: **Application exception handler** - weak symbol, only called for UNEXPECTED exceptions
- `0x1d0`: **Application interrupt handler** - weak symbol, only called for UNEXPECTED interrupts

The weak stubs at 0x1c2/0x1d0 are DEBUG helpers, not the main trap handler. They're only reached if an unexpected trap occurs (e.g., illegal instruction, unhandled interrupt).

### GCC Is Not Broken

The address calculation `0x00400800 << 3 = 0x02004000` is CORRECT. Initial analysis incorrectly interpreted the intermediate value as the final address.

### Timeout Confusion

Early testing used `TIMEOUT=5` which was too short. FreeRTOS takes ~10-20 seconds to boot due to slow UART output. Increasing to `TIMEOUT=30` revealed that tasks ARE created and scheduler DOES start.

---

## Root Cause Analysis

**Symptom**: mtimecmp remains at max value `0xFFFFFFFFFFFFFFFF`

**Evidence**:
1. `vPortSetupTimerInterrupt()` is called (confirmed in call trace)
2. Store instructions execute (PC reaches 0x1b10 and 0x1b1e)
3. No CLINT debug output (req_valid never asserted for CLINT)
4. No "MTIMECMP WRITE" messages

**Conclusion**: Store instructions to `0x02004000` are executed by CPU but never reach CLINT module.

**Possible Causes**:
1. **Bus routing issue**: Address decoder not routing 0x02004000 to CLINT
2. **Store buffer issue**: Stores stuck in pipeline or write buffer
3. **Bus arbiter issue**: CLINT slave port not properly connected
4. **Signal connectivity**: req_valid/req_we not wired correctly to CLINT

---

## Next Steps (Session 50)

1. **Add Bus Debug Tracing**:
   - Trace all bus transactions to address range 0x0200xxxx
   - Verify CLINT slave port is receiving requests
   - Check if simple_bus is routing addresses correctly

2. **Test CLINT Directly**:
   - Write simple test program that ONLY writes to mtimecmp
   - Verify CLINT can receive writes at all

3. **Check Signal Connectivity**:
   - Verify CLINT module instantiation in SoC
   - Check req_valid/req_we/req_addr signals are connected
   - Verify bus arbiter has CLINT in routing table

4. **Alternative Approaches**:
   - If bus issue unfixable, consider using MMIO writes directly from assembly
   - Add hardware breakpoint/watchpoint for address 0x02004000

---

## Files Modified This Session

None - investigation only

---

## Memory Map Reference

```
CLINT Base: 0x0200_0000
├── MSIP[0]:    0x0200_0000  (Machine Software Interrupt Pending)
├── ...
├── MTIMECMP[0]: 0x0200_4000  ← TARGET ADDRESS (not receiving writes)
├── MTIMECMP[1]: 0x0200_4008
├── ...
├── MTIME:      0x0200_BFF8  (reads working correctly)
└── MTIME+4:    0x0200_BFFC
```

---

## Testing Notes

**Working Tests**:
- Reading mtime (0x0200BFF8) works - atomic 64-bit read succeeds
- CLINT prescaler working (mtime increments every 10 cycles)

**Failing Tests**:
- Writing mtimecmp (0x02004000) - stores never reach peripheral

**Test Command**:
```bash
env XLEN=32 DEBUG_CLINT=1 TIMEOUT=30 ./tools/test_freertos.sh
```

---

## Conclusion

FreeRTOS is **functionally correct** and **properly configured**. The blocker is a **hardware bug in the bus interconnect** preventing mtimecmp writes from reaching the CLINT module.

**Status**: Ready for Session 50 bus debugging 🔧
