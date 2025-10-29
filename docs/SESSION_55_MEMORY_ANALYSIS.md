# Session 55: FreeRTOS Memory Layout Analysis (2025-10-28)

## Executive Summary

**Root Cause: Unknown** - Memory layout is valid, but FreeRTOS crashes during `main()` execution.

**Key Finding**: The crash occurs during/after `puts("Tasks created successfully!")` at PC ~0x23a4-0x23ae.

---

## Memory Layout Analysis

### 1. Overall Memory Map

```
IMEM (Instruction Memory):  0x00000000 - 0x0000FFFF (64 KB)
DMEM (Data Memory):         0x80000000 - 0x800FFFFF (1 MB)
```

### 2. Actual Memory Usage (from ELF)

```
Section          Start       End         Size        Usage
-------------------------------------------------------------
.text (IMEM)     0x00000000  0x00003DE8  15,848 B    15.48 KB
.rodata (DMEM)   0x80000000  0x80000710   1,808 B     1.77 KB
.data (DMEM)     0x80000710  0x80000720      16 B     0.02 KB
.bss (DMEM)      0x80000720  0x80041850 266,544 B   260.30 KB ⚠️
.heap (DMEM)     0x80041850  0x800C1850 524,288 B   512.00 KB
.stack (DMEM)    0x800C1850  0x800C2850   4,096 B     4.00 KB
-------------------------------------------------------------
Total DMEM Used: 0x80000000  0x800C2850 796,752 B   778.08 KB
DMEM Limit:      0x80000000  0x80100000 1,048,576 B 1024.00 KB
Remaining:                               251,824 B   245.92 KB ✅
```

**Status**: Memory layout is **VALID** - does not overflow DMEM boundaries.

### 3. BSS Section Analysis (260 KB)

The unusually large BSS section is due to FreeRTOS heap allocation:

```
Symbol          Address     Size        Purpose
-------------------------------------------------------------
ucHeap          0x80000980  0x40000     256 KB - FreeRTOS heap (heap_4.c)
xISRStack       0x80040980  0x800       2 KB   - ISR stack
uxTimerTaskStack 0x80041380 0x400       1 KB   - Timer task stack
uxIdleTaskStack 0x80041180  0x200       512 B  - Idle task stack
Other BSS vars  various     ~0x980      ~2.4 KB
```

**Note**: The linker script allocates a separate 512 KB `.heap` section (0x80041850-0x800C1850),
but FreeRTOS is configured to use `heap_4.c` which defines its own static `ucHeap[256KB]` array
in the BSS section. The linker `.heap` section is **unused** but still reserves space.

### 4. Stack Configuration

```
Initial Stack Pointer: 0x800C2850 (from linker script __stack_top)
Stack Bottom:          0x800C1850
Stack Size:            4096 bytes (4 KB)
Alignment:             16 bytes (RISC-V ABI compliant)
```

**FreeRTOS ISR Stack**: Uses `__freertos_irq_stack_top = __stack_top = 0x800C2850`

---

## Crash Analysis

### Execution Trace (from disassembly)

```assembly
main() at 0x22d4:
  0x22da: jal uart_init              ✅ Works
  0x22e4: jal puts [0x800005d0]       ✅ Works - "\n"
  0x22ee: jal puts [0x800004f4]       ✅ Works - "=============..."
  0x22f8: jal puts [0x80000520]       ✅ Works - "  FreeRTOS Blinky Demo"
  0x2302: jal puts [0x80000538]       ✅ Works - "  Target: RV1 RV32IMAFDC Core"
  0x2314: jal printf [formats]        ✅ Works - "  FreeRTOS Version: V10.5.1"
  0x2326: jal printf [formats]        ✅ Works - "  CPU Clock: 50000000 Hz"
  0x2334: jal printf [formats]        ✅ Works - "  Tick Rate: 1000 Hz"
  0x233e: jal puts [0x800005a8]       ✅ Works - "=============..."
  0x2358: jal xTaskCreate(vTask1)     ✅ Works - Task1 created
  0x2388: jal xTaskCreate(vTask2)     ✅ Works - Task2 created
  0x23a4: jal puts [0x80000624]       ❌ CRASH - "Tasks created successfully!"
  0x23ae: jal puts [0x80000640]       ← Never reached
  0x23b0: jal vTaskStartScheduler     ← Never reached
```

### UART Output Analysis

**Expected Output**:
```
========================================
  FreeRTOS Blinky Demo
  Target: RV1 RV32IMAFDC Core
  FreeRTOS Version: V10.5.1
  CPU Clock: 50000000 Hz
  Tick Rate: 1000 Hz
========================================

Tasks created successfully!
Starting FreeRTOS scheduler...
```

**Actual Output**:
```
========================================
FreeRTOSBlinkyDemo
Target:RV1RV32IMAFDCCore
FreeRTOSVersion:V10.5.1
CPUClock:50000000Hz
TickRate:1000Hz
========================================

Taskscreatedsu
```

**Observations**:
1. Missing spaces throughout (newlines '\n' are missing?)
2. "Tasks created successfully!" truncated to "Taskscreatedsu"
3. Crash occurs during or after the truncated puts() call
4. CPU ends up in infinite NOP loop

### String Data Verification

String at 0x80000624 (from .rodata section):
```
Hex:  54 61 73 6b 73 20 63 72  65 61 74 65 64 20 73 75
      63 63 65 73 73 66 75 6c  6c 79 21 00
Text: "Tasks created successfully!\0"
```

**Status**: String is **intact** in .rodata section ✅

---

## Potential Root Causes

### 1. ❌ Memory Overflow
- **Status**: RULED OUT
- DMEM usage: 778 KB / 1024 KB (245 KB remaining)
- Stack top: 0x800C2850 < DMEM limit 0x80100000

### 2. ❌ .rodata Corruption
- **Status**: RULED OUT
- String contents verified intact in ELF
- .rodata copied from IMEM to DMEM during startup

### 3. ⚠️ Stack Corruption (CANDIDATE)
- **Evidence**: Crash happens during function call sequence
- **Mechanism**: Return address on stack could be corrupted
- **Trigger**: `xTaskCreate()` allocates task control blocks from heap
- **Theory**: Heap corruption or stack overflow overwrites return address

### 4. ⚠️ Return Address Corruption (CANDIDATE)
- **Evidence**: CPU ends up in NOP loop (executing garbage memory)
- **Mechanism**: `jalr` return from `puts()` could jump to wrong address
- **Trigger**: Stack corruption or register corruption in puts()/UART code

### 5. ⚠️ UART/puts() Malfunction (CANDIDATE)
- **Evidence**:
  - Missing newlines/spaces in output
  - Truncated output "Taskscreatedsu" (14 chars of 28 chars)
  - Crash during puts() call
- **Mechanism**:
  - UART FIFO overflow?
  - Infinite loop in uart_putc()?
  - Bus hang on UART write?

### 6. ❌ FPU State Corruption
- **Status**: UNLIKELY
- FPU initialized correctly in startup.S
- No FP operations in main() before crash

---

## Startup Sequence Verification

From `start.S` and disassembly:

```assembly
_start (0x0):
  1. ✅ Disable interrupts (csrci mstatus, 8)
  2. ✅ Initialize SP = 0x800C2850
  3. ✅ Initialize GP = 0x80000f10
  4. ✅ Enable FPU (mstatus.FS = 01)
  5. ✅ Zero BSS (0x80000720 - 0x80041850)
  6. ✅ Copy .rodata (IMEM 0x3de8 → DMEM 0x80000000, size 0x710)
  7. ✅ Copy .data (IMEM 0x44f8 → DMEM 0x80000710, size 0x10)
  8. ✅ Set MTVEC = freertos_risc_v_trap_handler (0x2500)
  9. ✅ Enable timer/software interrupts (MIE bits 7,3)
  10. ✅ Call constructors (init_array - empty)
  11. ✅ Call main() (0x22d4)
```

**Status**: Startup sequence is **correct** ✅

---

## Heap Usage Analysis

### FreeRTOS Configuration (FreeRTOSConfig.h)
```c
#define configTOTAL_HEAP_SIZE  ( ( size_t ) ( 256 * 1024 ) )  // 256 KB
```

### Heap Implementation: heap_4.c
- Uses static `ucHeap[configTOTAL_HEAP_SIZE]` array in BSS
- Address: 0x80000980 - 0x80040980 (256 KB)
- Supports malloc/free with coalescence

### Heap Allocations Before Crash
1. `xTaskCreate(vTask1, ..., 256)`:
   - Task TCB: ~200 bytes
   - Task stack: 256 bytes
   - Total: ~456 bytes

2. `xTaskCreate(vTask2, ..., 256)`:
   - Task TCB: ~200 bytes
   - Task stack: 256 bytes
   - Total: ~456 bytes

**Total Heap Used**: ~912 bytes / 262,144 bytes (0.35%) ✅

---

## Next Steps for Debugging

### Option A: Stack Trace Analysis (RECOMMENDED)
1. Add PC tracing to capture exact crash location
2. Add SP (stack pointer) monitoring throughout execution
3. Trace `ra` (return address) register during function calls
4. Capture where control flow jumps to garbage memory

### Option B: Minimal Reproduction
1. Create bare-metal test that calls puts() in a loop
2. Isolate whether crash is in puts(), UART, or return handling
3. Test with different string lengths/contents

### Option C: UART Investigation
1. Add UART FIFO status monitoring
2. Check if UART hangs during transmission
3. Verify bus transactions complete correctly
4. Test UART with longer strings to see if truncation pattern repeats

### Option D: Memory Dump
1. Dump stack memory around SP=0x800C2850
2. Verify return addresses on stack are valid code addresses
3. Check for stack overflow (SP dropping below 0x800C1850)
4. Verify .rodata was copied correctly to DMEM

---

## Key Addresses Reference

```
Code Section:
  _start:                    0x00000000
  main:                      0x000022d4
  uart_init:                 0x00002434
  uart_putc:                 0x0000244e
  puts:                      0x00002462
  printf:                    0x000026ea
  xTaskCreate:               0x00000f88
  vTaskStartScheduler:       0x0000100a
  vPortSetupTimerInterrupt:  0x00001aca
  freertos_risc_v_trap_handler: 0x00002500

Data Section:
  .rodata start:             0x80000000
  .data start:               0x80000710
  .bss start:                0x80000720
  ucHeap (FreeRTOS):         0x80000980
  .heap start (unused):      0x80041850
  .stack bottom:             0x800C1850
  .stack top (SP init):      0x800C2850
  DMEM end:                  0x80100000

Strings:
  Banner separator:          0x800004f4
  "FreeRTOS Blinky Demo":    0x80000520
  "Target: RV1...":          0x80000538
  "Tasks created...":        0x80000624  ← Crash location
  "Starting FreeRTOS...":    0x80000640
```

---

## Conclusion

The memory layout is **valid and correct**. The crash is **NOT** due to memory overflow or
.rodata corruption. The issue appears to be related to:

1. **Runtime behavior** during puts() execution, OR
2. **Return address corruption** on the stack, OR
3. **UART transmission problem** causing hang/crash

The crash point is precisely identified: during/after `puts("Tasks created successfully!")`
at PC 0x23a4, which calls `puts()` at 0x2462 with string address 0x80000624.

**Recommended Next Step**: Add detailed PC and SP tracing to capture the exact instruction
where control flow breaks and identify whether it's a stack corruption or UART hang issue.
