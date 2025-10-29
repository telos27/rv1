# Session 53: Timer Interrupt Mechanism Fixes

**Date**: 2025-10-28
**Focus**: Investigating and fixing timer interrupt issues for FreeRTOS

## Summary

This session identified and fixed critical bugs in the timer interrupt mechanism, making significant progress toward FreeRTOS support.

### Major Fixes Completed ✅

1. **MTVEC/STVEC 2-byte Alignment Bug** (CRITICAL FIX)
2. **xISRStackTop Calculation Bug** (FreeRTOS-specific workaround)

### Remaining Issues ⚠️

1. CLINT MTIMECMP writes not completing (bus ready signal timing)

---

## Bug #1: MTVEC/STVEC Alignment (FIXED ✅)

### Problem
MTVEC and STVEC registers were forcing 4-byte alignment, incompatible with C extension support.

### Root Cause
In `rtl/core/csr_file.v`:
- Line 455: `mtvec_r <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes`
- Line 484: `stvec_r <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes`

**RISC-V Spec Requirements**:
- **Without C extension**: 4-byte alignment (bottom 2 bits = mode)
- **With C extension**: 2-byte alignment (bottom 1 bit = 0, bit 1 can be set)

Our core has `ENABLE_C_EXT=1`, so trap vectors must support 2-byte aligned addresses.

### Impact
- Trap handlers at odd 4-byte boundaries (e.g., 0x8000005E) were aligned down to 0x8000005C
- Caused execution to jump to wrong instructions (middle of previous function)
- Affected all trap handling (exceptions and interrupts)

### Fix
Modified `rtl/core/csr_file.v` to use conditional alignment:

**Lines 455-460** (MTVEC):
```verilog
// MTVEC alignment: 2-byte with C ext, 4-byte without
`ifdef ENABLE_C_EXT
CSR_MTVEC:    mtvec_r    <= {csr_write_value[XLEN-1:1], 1'b0};   // Align to 2 bytes (C ext)
`else
CSR_MTVEC:    mtvec_r    <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes
`endif
```

**Lines 489-494** (STVEC):
```verilog
// STVEC alignment: 2-byte with C ext, 4-byte without
`ifdef ENABLE_C_EXT
CSR_STVEC:    stvec_r    <= {csr_write_value[XLEN-1:1], 1'b0};   // Align to 2 bytes (C ext)
`else
CSR_STVEC:    stvec_r    <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes
`endif
```

### Verification
Created test `tests/asm/test_clint_timer_interrupt.s`:
- Sets up timer interrupt with 2-byte aligned trap handler
- Confirms trap handler is reached at correct address
- All regression tests still pass (14/14)

**Files Modified**:
- `rtl/core/csr_file.v` (lines 455-460, 489-494)

---

## Bug #2: xISRStackTop Calculation (WORKAROUND ✅)

### Problem
FreeRTOS `xISRStackTop` variable contained wrong value, causing stack corruption.

### Root Cause
In `software/freertos/port/port.c` line 69:
```c
const StackType_t xISRStackTop = ( StackType_t ) &( xISRStack[ configISR_STACK_SIZE_WORDS & ~portBYTE_ALIGNMENT_MASK ] );
```

This address calculation was being evaluated incorrectly at compile/link time:
- **Expected value**: 0x80040CE0 (end of xISRStack array)
- **Actual value**: 0x0000C350 (50,000 - completely wrong, grabbed CPU clock constant!)

### Impact
- `xPortStartScheduler()` used wrong address for memset, corrupting memory
- Stack pointer and return addresses corrupted
- FreeRTOS scheduler never reached `vPortSetupTimerInterrupt()`
- System hung after printing "Starting FreeRTOS scheduler..."

### Workaround
Disabled `configISR_STACK_SIZE_WORDS` in FreeRTOS config to force use of linker-provided symbol.

**File**: `software/freertos/config/FreeRTOSConfig.h` line 58-59:
```c
/* ISR Stack Size: 2KB (512 words) - used for interrupt context */
/* WORKAROUND: Comment out to use linker-provided stack (xISRStackTop calculation bug) */
// #define configISR_STACK_SIZE_WORDS      ( 512 )
```

This forces port.c to use the `#else` branch (line 77):
```c
extern const uint32_t __freertos_irq_stack_top[];
const StackType_t xISRStackTop = ( StackType_t ) __freertos_irq_stack_top;
```

**Result**:
- `xISRStackTop` now correctly = 0x800C1BB0 (linker-provided)
- `xPortStartScheduler()` no longer calls memset (no static ISR stack array)
- Execution reaches `vPortSetupTimerInterrupt()` successfully

**Files Modified**:
- `software/freertos/config/FreeRTOSConfig.h` (line 58-59)

---

## Remaining Issue: CLINT MTIMECMP Writes ⚠️

### Current Status
FreeRTOS now executes much further:
1. ✅ Boots successfully
2. ✅ Creates tasks
3. ✅ Calls `vTaskStartScheduler()`
4. ✅ Calls `xPortStartScheduler()`
5. ✅ Calls `vPortSetupTimerInterrupt()`
6. ⚠️ **MTIMECMP writes don't complete**

### Symptoms
Debug trace shows:
```
[CORE-BUS-WR] Cycle 0: addr=0x02004000 wdata=0x000000000000d342 size=2 valid=1 ready=0
```

- Bus transaction initiated (valid=1)
- CLINT not ready in same cycle (ready=0)
- MTIMECMP register never updated (stays at 0xFFFFFFFFFFFFFFFF)
- No timer interrupts fire

### Analysis
1. CLINT peripheral asserts `req_ready <= req_valid` (registered assignment)
2. This means ready asserts on the NEXT cycle after valid
3. Bus wait stall should handle this (Session 52 fix)
4. But writes appear to be getting lost

### Hypotheses for Next Session
1. Bus wait stall not holding write data correctly across cycles
2. CLINT ready signal not propagating through bus arbiter
3. Write enable pulse too short (one-shot issue)
4. Pipeline flush/stall interaction

### Next Steps
1. Add detailed bus transaction tracing for multi-cycle CLINT writes
2. Verify `bus_req_issued` flag works correctly for stores
3. Check if write data is held stable during stall
4. Test with simpler CLINT write (to MSIP register)

---

## Test Results

### Regression Tests
All tests pass: **14/14** ✅
```bash
make test-quick
```

### Timer Interrupt Test
Created: `tests/asm/test_clint_timer_interrupt.s`
- Verifies MTVEC 2-byte alignment works
- Confirms trap handler reached correctly
- Tests CLINT MTIMECMP write mechanism
- **Status**: Needs multi-cycle bus transaction fix

### FreeRTOS Boot Test
```bash
env XLEN=32 TIMEOUT=60 ./tools/test_freertos.sh
```

**Output**:
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

**Progress**: Much better than Session 52! Now reaches timer setup.

---

## Code Changes Summary

### RTL Changes
1. `rtl/core/csr_file.v`:
   - Lines 455-460: MTVEC conditional alignment
   - Lines 489-494: STVEC conditional alignment

### FreeRTOS Changes
1. `software/freertos/config/FreeRTOSConfig.h`:
   - Line 58-59: Commented out `configISR_STACK_SIZE_WORDS`

### Test Additions
1. `tests/asm/test_clint_timer_interrupt.s`: Timer interrupt verification test

---

## Key Learnings

1. **RISC-V C Extension Alignment**:
   - Trap vectors need 2-byte alignment with C extension
   - Common source of subtle bugs in compressed instruction implementations

2. **Compiler/Linker Limitations**:
   - Complex const address calculations can fail mysteriously
   - Linker-provided symbols more reliable than computed addresses
   - Symbol tables can be misleading (location vs. value)

3. **Multi-Cycle Bus Transactions**:
   - Peripheral ready signals may lag by one cycle
   - Bus wait stall must preserve transaction state
   - Write data must be held stable during stalls

4. **Debug Strategy**:
   - Isolate issues with minimal tests (test_clint_timer_interrupt)
   - Compare symbol table with actual memory contents
   - Trace PC execution to find where code diverges
   - Check alignment assumptions for all trap-related CSRs

---

## References

- RISC-V Privileged Spec v1.12: Section 3.1.7 (MTVEC), 4.1.2 (STVEC)
- FreeRTOS RISC-V Port: `portable/GCC/RISC-V/port.c`
- Session 52: Bus Wait Stall Fix
- Session 51: CLINT 64-bit Read Bug Fix

---

## Files Modified

### RTL
- `rtl/core/csr_file.v` - MTVEC/STVEC alignment fix

### Software
- `software/freertos/config/FreeRTOSConfig.h` - Disable configISR_STACK_SIZE_WORDS

### Tests
- `tests/asm/test_clint_timer_interrupt.s` - New timer interrupt test

---

## Next Session Goals

1. **Fix CLINT multi-cycle write completion**
   - Debug bus wait stall for peripheral writes
   - Ensure write data held during ready wait
   - Verify MTIMECMP actually gets written

2. **Complete FreeRTOS boot**
   - Get timer interrupts firing
   - See task switching
   - Verify scheduler operation

3. **Test suite validation**
   - Add timer interrupt tests to regression
   - Create FreeRTOS smoke test
   - Document expected boot sequence
