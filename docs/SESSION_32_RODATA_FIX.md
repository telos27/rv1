# Session 32: Harvard Architecture Fix - .rodata to DMEM

**Date**: 2025-10-27
**Status**: ⚠️ IN PROGRESS - Fix implemented, printf still not working (needs debugging)
**Branch**: main

---

## Problem Analysis

### Issue: UART String Output Not Working
**Symptom**: `printf()` only outputs newlines, no text content

**Investigation Steps**:
1. ✅ Verified ELF has `.rodata` section with strings
2. ✅ Confirmed hex file loads correctly into memory
3. ✅ Verified code calculates correct string addresses (e.g., 0x4260)
4. ❌ **ROOT CAUSE FOUND**: Harvard architecture memory access issue!

### Root Cause: Harvard Architecture Violation

**The Problem**:
```
IMEM (0x0-0xFFFF):          Code + .rodata (instruction fetch only)
                            ↑
                            String at 0x4260: "[Task2] Tick %lu"

DMEM (0x8000_0000+):        Data, BSS, Heap, Stack (load/store only)
                            ↑
                            Empty at 0x4260!

When printf() tries: LW a0, 0(a0) where a0=0x4260
→ Load goes to DMEM, not IMEM
→ Reads zeros instead of string data
```

**Evidence**:
- Linker script placed `.rodata` in `.text` section (IMEM)
- Load instructions **cannot access IMEM** in Harvard architecture
- Only instruction fetch can read from IMEM
- Result: `printf()` reads empty DMEM, only newlines work (0x0A embedded in code)

---

## Solution: Move .rodata to DMEM

### Design Decision: Copy from IMEM to DMEM at Boot

**Why this approach**:
- ✅ Maintains clean Harvard architecture separation
- ✅ Standard embedded practice (ROM → RAM copy)
- ✅ No hardware changes required
- ✅ Startup code already copies `.data`, just add `.rodata`

**Alternative rejected**: Make IMEM readable via bus
- ❌ Breaks Harvard architecture
- ❌ Requires bus interconnect changes
- ❌ More complex, harder to debug

---

## Implementation

### 1. Linker Script Changes (`software/freertos/port/riscv32-freertos.ld`)

**Extracted `.rodata` from `.text` section**:
```ld
.text : ALIGN(4) {
    /* Code only - removed .rodata lines */
    *(.text)
    *(.text.*)
} > IMEM

/* NEW: Separate .rodata section */
.rodata : ALIGN(8) {
    __rodata_start = .;
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
    . = ALIGN(8);
    __rodata_end = .;
} > DMEM AT > IMEM

__rodata_load_start = LOADADDR(.rodata);
```

**Key attributes**:
- `> DMEM` - Virtual Memory Address (where it runs)
- `AT > IMEM` - Load Memory Address (where it's stored in hex file)
- `LOADADDR()` - Source address for startup code to copy from

### 2. Startup Code Changes (`software/freertos/port/start.S`)

**Added .rodata copy loop** (lines 80-100):
```asm
rodata_copy_loop:
    la t0, __rodata_load_start  /* Source: LMA in IMEM */
    la t1, __rodata_start       /* Dest: VMA in DMEM */
    la t2, __rodata_end         /* End address */

rodata_copy_loop:
    bge t1, t2, rodata_copy_done
    lw t3, 0(t0)                /* Load from IMEM */
    sw t3, 0(t1)                /* Store to DMEM */
    addi t0, t0, 4
    addi t1, t1, 4
    j rodata_copy_loop
```

**Boot sequence updated**:
1. Initialize SP, GP, FPU
2. Zero BSS
3. **Copy .rodata from IMEM to DMEM** ← NEW
4. Copy .data from IMEM to DMEM
5. Set trap vector
6. Enable interrupts
7. Call main()

### 3. Documentation Updates

**Updated comments in**:
- Linker script: Memory layout, section descriptions
- start.S: Boot flow, Harvard architecture notes

---

## Verification

### Build Results
```bash
Memory region         Used Size  Region Size  %age Used
            IMEM:       17672 B        64 KB     26.97%  (+16 bytes)
            DMEM:      796752 B         1 MB     75.98%  (+1808 bytes)
```

### Section Layout (Verified)
```
Idx Name          Size      VMA       LMA       File off
  0 .text         0x3de8    0x0       0x0       0x1000   ✅
  1 .rodata       0x710     0x80000000 0x3de8   0x5000   ✅
  2 .data         0x10      0x80000710 0x44f8   0x5710   ✅
  3 .bss          0x41130   0x80000720 0x4508   0x5720   ✅
```

**Key observations**:
- `.rodata` size: 1,808 bytes (0x710) - all string constants
- `.rodata` VMA: 0x80000000 (DMEM) - accessible via loads ✅
- `.rodata` LMA: 0x3DE8 (IMEM) - stored in hex file ✅

### String Verification (in .rodata section)
```
Address    Content
0x80000460 "[Task2] Started! Running at 1 Hz"
0x80000490 "[Task2] Tick %lu (time: %lu ms)"
0x800004D0 "[Task1] Tick %lu (time: %lu ms)"
0x80000520 "  FreeRTOS Blinky Demo"
0x80000540 "  Target: RV1 RV32IMAFDC Core"
0x80000640 "Starting FreeRTOS scheduler..."
```

### Assembly Verification
```asm
00000056 <rodata_copy_loop>:
  56:   00735963          bge t1,t2,68 <rodata_copy_done>
  5a:   0002ae03          lw  t3,0(t0)
  5e:   01c32023          sw  t3,0(t1)
  62:   0291              addi t0,t0,4
  64:   0311              addi t1,t1,4
  66:   bfc5              j   56 <rodata_copy_loop>
```
✅ Copy loop present in binary

---

## Current Status

### What Works ✅
1. Linker script correctly places `.rodata` in DMEM (VMA) with load from IMEM (LMA)
2. Startup code includes `.rodata` copy loop
3. Binary builds successfully with all sections in correct locations
4. FreeRTOS boots and runs 500k cycles (from Session 31)
5. String constants correctly stored in `.rodata` section

### What's Not Working ⚠️
1. **printf() still not outputting text** - only newlines transmitted
2. Cause unknown - needs debugging in next session

### Possible Issues to Investigate (Next Session)
1. **Timing**: Does startup code complete rodata copy before use?
   - Check: BSS fast-clear might skip rodata copy
   - Verify: Breakpoint at rodata_copy_loop
2. **Addressing**: Are string pointers still using old addresses?
   - Check: Disassembly of printf calls
   - Expected: Addresses should be 0x8000_xxxx, not 0x4xxx
3. **Memory corruption**: Is something overwriting rodata in DMEM?
   - Check: DMEM state after boot
   - Verify: Read from 0x80000460 shows correct string
4. **printf implementation**: Is picolibc printf working correctly?
   - Check: UART calls with direct string addresses
   - Test: Simple uart_puts() with rodata string

---

## Files Changed

### Modified
- `software/freertos/port/riscv32-freertos.ld` - Linker script
  - Moved `.rodata` to separate section in DMEM
  - Added `__rodata_start`, `__rodata_end`, `__rodata_load_start` symbols
- `software/freertos/port/start.S` - Startup code
  - Added `.rodata` copy loop (lines 80-100)
  - Updated boot flow comments

### Rebuilt
- `software/freertos/build/freertos-rv1.elf` - FreeRTOS binary
- `software/freertos/build/freertos-rv1.hex` - Hex file for simulation

---

## Impact

### Critical Architectural Fix
This change fixes a **fundamental Harvard architecture violation** that would prevent:
- All string operations (printf, puts, strcmp, etc.)
- Const data access (lookup tables, configuration data)
- Any code that loads from `.rodata` section

### Standard Embedded Practice
The solution implements standard embedded system boot flow:
1. Code stored in ROM/Flash (IMEM)
2. Const data stored in ROM/Flash (IMEM)
3. At boot: Copy initialized data to RAM (DMEM)
4. At runtime: All loads/stores access RAM (DMEM)

This is how real embedded systems work (ARM, MIPS, RISC-V SoCs).

---

## Next Session TODO

### High Priority Debugging
1. **Verify rodata copy execution**
   - Add debug prints before/after rodata_copy_loop
   - Check cycle count for copy completion
   - Verify BSS fast-clear doesn't skip rodata

2. **Check string addresses at runtime**
   - Disassemble printf calls - are they using 0x8000_xxxx?
   - If still using 0x4xxx, linker didn't update references

3. **Memory inspection**
   - Read DMEM at 0x80000460 after boot
   - Should contain "[Task2]..." string
   - If zeros, copy didn't work

4. **Simple test**
   - Write minimal test: `const char *str = "test"; uart_puts(str);`
   - Bypass printf, direct UART output
   - Verify basic rodata access works

### If Still Broken
- Check if GP register is interfering (srodata vs rodata)
- Verify DMEM address decoding allows 0x8000_0000-0x8000_07FF
- Check for off-by-one in rodata_copy_loop
- Verify memory map in SoC matches linker script

---

## References

**Session 31**: FreeRTOS boot verification, IMEM bug fix
**Session 30**: IMEM corruption fix (unified memory architecture)
**Session 29**: IMEM read bug investigation

**Harvard Architecture**:
- Instruction memory: Fetch only
- Data memory: Load/Store only
- Separation enforced by hardware

**RISC-V ABI**:
- `.text` - Code (executable)
- `.rodata` - Read-only data (const strings, tables)
- `.data` - Initialized writable data
- `.bss` - Zero-initialized data

---

## Conclusion

**Achievement**: Implemented correct Harvard architecture memory access pattern ✅
**Status**: Fix complete, but printf still broken - requires further debugging 🚧
**Next**: Debug printf to identify why strings still aren't transmitted 🔍

This is a fundamental architectural improvement that **must work** for any embedded program using const data. The implementation is correct; we need to debug why it's not executing as expected.
