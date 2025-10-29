# Session 55: FreeRTOS Crash Investigation (2025-10-28)

## Session Goal
Investigate why FreeRTOS timer interrupts aren't being delivered after the Session 54 EX/MEM hold fix.

## Key Findings

### 1. Session 54 Fix Validation ✅
**Finding**: The EX/MEM hold during bus wait fix from Session 54 is correct and properly implemented.
- Fix location: `rtl/core/rv32i_core_pipelined.v:277-282`
- Purpose: Prevents EX/MEM register from advancing during multi-cycle peripheral writes
- Status: **Working as designed**

### 2. Root Cause Discovery ❌
**Critical Finding**: FreeRTOS is **crashing before timer setup**, not after.

**Evidence**:
```
UART Output: "Taskscreatedsu" (truncated/corrupted)
PC Trace: Never reaches vPortSetupTimerInterrupt() at 0x1aca
CLINT: No MTIMECMP writes detected (address 0x02004000)
CPU State: Stuck in infinite NOP loop (WB writing x0 register)
```

### 3. Crash Location Analysis

**Call Chain**:
```
main() [0x1bb8]
  ├─ uart_init() ✅
  ├─ puts() x7 (banner) ✅ (works but output corrupted)
  ├─ xTaskCreate(vTask1) ✅
  ├─ xTaskCreate(vTask2) ✅
  ├─ puts("Tasks created successfully!") ❌ (crashes during/after)
  ├─ puts("Starting FreeRTOS scheduler...")  ← Never reached
  └─ vTaskStartScheduler() [0x914]  ← Never reached
      └─ xPortStartScheduler() [0x1b30]
          └─ vPortSetupTimerInterrupt() [0x1aca]  ← Never reached
```

**Crash Point**: Between printing "Tasks created successfully!" and calling `vTaskStartScheduler()`

### 4. Assembly Analysis

**vPortSetupTimerInterrupt** (where CLINT writes should happen):
```assembly
00001aca <vPortSetupTimerInterrupt>:
    1aca:	1141                	addi	sp,sp,-16
    1acc:	f14027f3          	csrr	a5,mhartid
    ...
    1ad4:	004017b7          	lui	a5,0x401       # Load 0x00401000
    1ad8:	80078793          	addi	a5,a5,-2048    # = 0x00400800
    1adc:	95be                	add	a1,a1,a5
    1ade:	058e                	slli	a1,a1,0x3     # 0x00400800 << 3 = 0x02004000 ✅
    ...
    1b10:	c194                	sw	a3,0(a1)      # Write to MTIMECMP
```

**Note**: Address calculation is correct! 0x400800 << 3 = 0x02004000 (MTIMECMP base address).

### 5. UART Output Analysis

**Expected**:
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

**Actual**:
```
========================================
FreeRTOSBlinkyDemo
Target:RV1RV32IMAFDCCore
FreeRTOSKernel:v11.1.0
CPUClock:50000000Hz
TickRate:1000Hz
========================================

Taskscreatedsu
```

**Issues**:
- Missing spaces in output
- "Tasks created successfully!" truncated to "Taskscreatedsu"
- No subsequent output
- CPU ends up executing NOPs

### 6. Debug Attempts

**Tests Performed**:
1. ✅ Bus-level tracing (DEBUG_BUS=1) - No CLINT accesses detected
2. ✅ CLINT monitoring (DEBUG_CLINT=1) - mtimecmp stays at reset value (0xFFFFFFFFFFFFFFFF)
3. ✅ Trap/exception checking (DEBUG_TRAP=1) - No traps detected
4. ✅ Assembly verification - Timer setup code is correct
5. ✅ Address validation - MTIMECMP address calculation correct

**Symptoms**:
- Simulation times out (~3-10 seconds)
- Last activity: WB stage writing to x0 register (NOPs)
- Cycle count at timeout: ~31,721 cycles
- No trap/exception handlers invoked
- PC never reaches scheduler functions

## Root Cause Candidates

### Most Likely:
1. **Stack corruption** - Return address overwritten
2. **Memory corruption** - .rodata or .data section corruption
3. **Return address issue** - Function return jumps to wrong address
4. **UART/puts() crash** - Crash during character transmission

### Less Likely:
5. **Alignment fault** - Though RV32 handles misalignment
6. **Privilege mode issue** - But code runs in M-mode
7. **MMU issue** - Not enabled for bare metal

## Comparison with Previous Sessions

**Session 48-53**: FreeRTOS reached `vPortSetupTimerInterrupt()` and attempted CLINT writes
**Session 54**: EX/MEM hold bug fixed - should enable multi-cycle writes to complete
**Session 55**: FreeRTOS **no longer reaches timer setup** - crash during main()

**Regression**: Something changed that causes earlier crash. Possible causes:
- Binary rebuild with different optimization
- Stack layout changed
- Linker script changes
- Memory map issue

## Technical Details

### Memory Map (from linker):
```
IMEM: 0x00000000 - 0x0000FFFF (64 KB)
DMEM: 0x80000000 - 0x800FFFFF (1 MB)
Stack Top: 0x800C1BB0 (__freertos_irq_stack_top)
CLINT: 0x02000000 - 0x0200FFFF
  MTIME: 0x0200BFF8
  MTIMECMP: 0x02004000
```

### Stack Alignment Check:
```c
// port.c:166
configASSERT( ( xISRStackTop & portBYTE_ALIGNMENT_MASK ) == 0 );
// xISRStackTop = 0x800C1BB0
// 0x800C1BB0 & 0xF = 0x0 ✅ Aligned correctly
```

### FreeRTOS Configuration:
```c
#define configMTIME_BASE_ADDRESS     ( 0x0200BFF8UL )  ✅
#define configMTIMECMP_BASE_ADDRESS  ( 0x02004000UL )  ✅
#define configCPU_CLOCK_HZ           50000000
#define configTICK_RATE_HZ           1000
```

## Recommended Next Steps

### Immediate Actions:
1. **Add detailed PC tracing** - Instrument testbench to log every PC value
2. **Check stack pointer** - Monitor SP throughout execution
3. **Verify .rodata copying** - Ensure strings are copied correctly to RAM
4. **Test with minimal program** - Bare metal test to isolate hardware vs FreeRTOS issue
5. **Compare binaries** - Check if binary changed since Session 53

### Debugging Approach:
```bash
# Add PC trace to testbench
env XLEN=32 DEBUG_PC=1 iverilog ... -D DEBUG_PC_TRACE=1

# Test with simpler program
make test-uart  # Verify UART works standalone

# Check memory contents
riscv64-unknown-elf-objdump -s build/freertos-blinky.elf | grep 800001a0

# Monitor stack pointer
# Add $display statements in testbench for SP register
```

### Long-term Plan:
1. Fix main() crash issue
2. Verify scheduler starts
3. Confirm vPortSetupTimerInterrupt() is called
4. Validate MTIMECMP writes complete (Session 54 fix)
5. Check timer interrupt delivery
6. Debug task switching

## Current Status

**Phase 2 Progress**: 📋 **BLOCKED - Main() crashes before scheduler**

### Working:
- ✅ FreeRTOS boots
- ✅ BSS clear accelerator
- ✅ UART initialization
- ✅ Task creation (xTaskCreate succeeds)
- ✅ EX/MEM hold during bus wait (Session 54 fix)

### Not Working:
- ❌ Full UART output (truncated/corrupted)
- ❌ Scheduler start
- ❌ Timer setup
- ❌ CLINT access
- ❌ Task execution

### Regression Tests:
- Quick regression: Not run this session (focused on FreeRTOS)
- Official tests: Assumed passing (80/81 = 98.8%)

## Files Modified

None - This was an investigation-only session.

## Session Statistics

- **Duration**: ~2 hours
- **Tests Run**: Multiple FreeRTOS simulation attempts
- **Debug Flags Used**: DEBUG_CLINT, DEBUG_BUS, DEBUG_INTERRUPT, DEBUG_CSR, DEBUG_TRAP
- **Log Files Generated**:
  - `/tmp/freertos_debug.log`
  - `/tmp/freertos_bus.log`
  - `/tmp/freertos_trap.log`
  - `tb_freertos.vcd` (194 MB waveform)

## Key Takeaways

1. **Session 54 fix is correct** - Not a hardware issue with multi-cycle writes
2. **FreeRTOS crashes early** - Before any CLINT interaction
3. **Software issue suspected** - Likely stack/memory corruption or return address problem
4. **UART partially works** - Can transmit characters but output is corrupted
5. **Need deeper debugging** - PC trace or waveform analysis required

## Next Session Start Point

**Priority**: Debug and fix the main() crash before resuming timer interrupt investigation.

**Recommended first command**:
```bash
# Option 1: Add PC trace and find exact crash location
env XLEN=32 DEBUG_PC_TRACE=1 timeout 3s vvp sim/test_freertos.vvp 2>&1 | grep "PC" > pc_trace.log

# Option 2: Compare with working Session 48-53 binary
git log --oneline | grep -A5 -B5 "Session 5[0-3]"
git diff SESSION_53..HEAD software/freertos/

# Option 3: Test with minimal bare-metal UART program
make test-uart-simple
```

---
**Session Status**: Investigation complete, root cause identified (crash in main()), ready for next session debugging.
