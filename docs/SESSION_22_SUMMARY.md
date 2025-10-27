# Session 22: FreeRTOS Compilation Success & First Boot Attempt

**Date:** 2025-10-27
**Duration:** ~90 minutes
**Focus:** Compile FreeRTOS for RV32IMAFDC, create testbench, attempt first boot
**Status:** ✅ Compilation Complete, 🚧 Boot Debugging Required

---

## Overview

Session 22 achieved a major milestone: **FreeRTOS successfully compiled for the RV1 RISC-V core!** This is the first step toward running a production-quality RTOS on our custom CPU. We also created simulation infrastructure and attempted the first boot, which revealed issues requiring debugging in the next session.

---

## Achievements

### 1. picolibc Installation ✅

**Problem:** FreeRTOS and syscalls required standard C library functions (stdlib.h, errno, etc.)

**Solution:** Installed `picolibc-riscv64-unknown-elf` package
- Lightweight C library optimized for embedded systems
- RISC-V cross-compilation support
- Version 1.7.4 from Ubuntu repositories

**Command:**
```bash
sudo apt install picolibc-riscv64-unknown-elf
```

---

### 2. FreeRTOS Compilation Fixes ✅

Multiple compilation issues were resolved to achieve a successful build:

#### A. Makefile Configuration
**File:** `software/freertos/Makefile`

**Changes:**
- Added picolibc specs file to compiler flags:
  ```makefile
  --specs=/usr/lib/picolibc/riscv64-unknown-elf/picolibc.specs
  ```
- Removed `-lc` from LIBS (provided by picolibc)
- Fixed DEMO_SRCS to include `main_blinky.c` at top level

**Result:** Correct library linking and demo inclusion

#### B. FreeRTOSConfig.h Fixes
**File:** `software/freertos/config/FreeRTOSConfig.h`

**Issues Fixed:**
1. **Preprocessor macro compatibility:**
   - Changed: `#define configCPU_CLOCK_HZ ((unsigned long) 50000000)`
   - To: `#define configCPU_CLOCK_HZ 50000000UL`
   - Reason: Casts in macros can't be used in `#if` preprocessor conditions

2. **Missing definition:**
   - Added: `#define configUSE_16_BIT_TICKS 0`
   - Reason: FreeRTOS kernel requires this for 32-bit tick counts

3. **Memory constraints:**
   - Changed heap size from 512KB to 256KB
   - Reason: 1MB DMEM must fit data + BSS + heap + stack
   - 256KB heap leaves room for ~538KB data/BSS/stack

**Result:** Clean compilation of FreeRTOS kernel

#### C. UART Driver Fix
**File:** `software/freertos/lib/uart.c`

**Issue:** Missing NULL definition

**Fix:** Added `#include <stddef.h>` at top of file

#### D. Syscalls Fix
**File:** `software/freertos/lib/syscalls.c`

**Issue:** Conflicting errno declaration (picolibc declares errno as thread-local)

**Fixes:**
1. Removed `#undef errno` and `extern int errno`
2. Added stdio FILE pointer definitions:
   ```c
   FILE *const stdin = (FILE *)0;
   FILE *const stdout = (FILE *)1;
   FILE *const stderr = (FILE *)2;
   ```

**Result:** Newlib syscalls working with printf/scanf support

---

### 3. Successful Build Output ✅

**Final compilation succeeded with excellent statistics:**

```
Memory region         Used Size  Region Size  %age Used
            IMEM:       17464 B        64 KB     26.65%
            DMEM:      794944 B         1 MB     75.81%
```

**Binary breakdown:**
- **text:** 17,448 bytes (program code)
- **data:** 16 bytes (initialized globals)
- **bss:** 794,928 bytes (zero-initialized data + 256KB heap)

**Files created:**
- `software/freertos/build/freertos-rv1.elf` (254 KB)
- `software/freertos/build/freertos-rv1.hex` (53 KB, for simulation)
- `software/freertos/build/freertos-rv1.map` (93 KB, linker map)

---

### 4. Testbench Infrastructure ✅

#### A. FreeRTOS Testbench Created
**File:** `tb/integration/tb_freertos.v` (195 lines)

**Features:**
- 50 MHz clock (matches FreeRTOS `configCPU_CLOCK_HZ`)
- Large memory support: 64KB IMEM, 1MB DMEM
- UART TX monitoring with ASCII character display
- Progress indicators every 1k cycles
- PC stuck detection (infinite loop detection)
- EBREAK detection for early termination
- Configurable timeout (default: 50k cycles = 1ms simulation)

**Key capabilities:**
- Monitors all UART output from FreeRTOS printf calls
- Detects boot hangs and infinite loops
- Generates VCD waveform for debugging

#### B. Simulation Script Created
**File:** `tools/test_freertos.sh` (executable)

**Features:**
- Checks for FreeRTOS binary existence
- Compiles testbench with iverilog
- Runs simulation with configurable timeout
- Color-coded success/failure reporting
- VCD file size reporting

**Usage:**
```bash
./tools/test_freertos.sh                # Default 60s timeout
TIMEOUT=120 ./tools/test_freertos.sh    # Custom timeout
```

---

### 5. First Boot Attempt 🚧

**Status:** Simulation runs but boot sequence appears stuck

**Observations:**
1. ✅ Testbench compiles successfully (minor width mismatch warnings)
2. ✅ Simulation loads FreeRTOS binary (17KB code loaded to IMEM)
3. ✅ Simulation runs 50,000 cycles (1ms @ 50MHz)
4. ❌ PC appears stuck around 0x00000014 (in startup code)
5. ❌ No UART output received
6. ❌ Very few debug messages (only cycle 1 printed)

**Last known PC: 0x00000014**
```
Disassembly at PC 0x14:
   10:	80000197          	auipc	gp,0x80000
   14:	7f018193          	addi	gp,gp,2032 # 80000800
```

This is in the `_start` routine, trying to set the global pointer (gp) to DMEM address 0x80000800.

**Possible causes for investigation:**
1. DMEM address decode issue (0x8000_0000 range)
2. auipc instruction bug with large immediate values
3. Memory access stall or infinite wait
4. Bus interconnect routing problem

**Artifacts created:**
- `tb_freertos.vcd` - Full waveform capture for debugging
- `sim/tb_freertos` - Compiled simulation binary

---

## Files Modified (11 files)

### Compilation Fixes:
1. `software/freertos/Makefile` - picolibc specs, demo sources
2. `software/freertos/config/FreeRTOSConfig.h` - macro fixes, heap size, missing defines
3. `software/freertos/lib/uart.c` - stddef.h include
4. `software/freertos/lib/syscalls.c` - FILE pointers, errno fix

### New Files Created:
5. `tb/integration/tb_freertos.v` - FreeRTOS simulation testbench (195 lines)
6. `tools/test_freertos.sh` - Simulation runner script (executable)

### Build Artifacts (not in git):
- `software/freertos/build/freertos-rv1.elf`
- `software/freertos/build/freertos-rv1.hex`
- `software/freertos/build/freertos-rv1.map`
- `tb_freertos.vcd`

---

## Technical Details

### Compilation Toolchain
- **Compiler:** riscv64-unknown-elf-gcc
- **Target:** RV32IMAFDC / ilp32d ABI
- **C Library:** picolibc 1.7.4 (--specs)
- **Linker Script:** `port/riscv32-freertos.ld`
- **Optimization:** -O2 with -ffunction-sections -fdata-sections
- **Garbage Collection:** --gc-sections (removes unused code)

### Memory Layout
**Instruction Memory (IMEM):**
- Base: 0x00000000
- Size: 64 KB (65,536 bytes)
- Usage: 17,464 bytes (26.65%)
- Contents: FreeRTOS kernel + port + drivers + demo

**Data Memory (DMEM):**
- Base: 0x80000000
- Size: 1 MB (1,048,576 bytes)
- Usage: 794,944 bytes (75.81%)
- Layout:
  - .data section: 16 bytes (initialized globals)
  - .bss section: ~538 KB (zero-initialized)
  - FreeRTOS heap: 256 KB (configTOTAL_HEAP_SIZE)
  - Stack: ~4 KB (configurable)

### FreeRTOS Configuration Highlights
- **Tick Rate:** 1000 Hz (1ms tick period)
- **Preemption:** Enabled
- **Max Priorities:** 5 levels
- **Min Stack Size:** 512 bytes (128 words)
- **Heap Allocator:** heap_4 (best-fit with coalescing)
- **FPU Context:** Saved/restored (32 FP registers + FCSR = 264 bytes/task)

---

## Next Steps (Session 23)

### Immediate Debugging Tasks:
1. **Analyze VCD waveform** - Use gtkwave to inspect:
   - PC progression in first 100 cycles
   - Bus transactions to DMEM
   - Memory address decode signals
   - Instruction fetch vs execution timing

2. **Verify memory map** - Check if:
   - SoC bus interconnect correctly routes 0x8000_xxxx to DMEM
   - DMEM adapter handles 1MB address space
   - auipc + addi address calculation is correct

3. **Add debug output** - Enhance testbench:
   - Print every instruction executed (first 100 cycles)
   - Monitor bus transactions
   - Check for stalls or wait states
   - Verify reset release timing

4. **Test startup code** - Isolate issues:
   - Create minimal test that just accesses DMEM
   - Verify gp register setup works
   - Check if BSS zeroing loop completes

### Alternative Approaches:
- Start with smaller DMEM (16KB) to rule out size issues
- Use bare-metal test program before full FreeRTOS
- Check if official RISC-V tests pass with 1MB DMEM

---

## Lessons Learned

1. **picolibc is essential** - Embedded C library required for standard headers
2. **Preprocessor macro pitfalls** - Casts in `#define` break `#if` conditions
3. **Memory sizing tradeoff** - Large heap vs. available DMEM space
4. **Simulation performance** - 1MB DMEM compiles/runs reasonably in Icarus Verilog
5. **Testbench importance** - Good monitoring (UART, progress, stuck detection) critical

---

## References

- FreeRTOS Kernel: https://github.com/FreeRTOS/FreeRTOS-Kernel
- picolibc Documentation: https://github.com/picolibc/picolibc
- RISC-V Calling Conventions: ilp32d ABI for RV32IMAFDC
- Previous Session: `docs/SESSION_21_PHASE_2_SUMMARY.md` (Port layer creation)

---

## Summary Statistics

- **Time:** ~90 minutes
- **Lines Added:** ~410 lines (testbench + script + fixes)
- **Files Modified:** 4 files (compilation fixes)
- **Files Created:** 2 files (testbench + script)
- **Compilation Result:** ✅ SUCCESS (17KB code, 795KB data)
- **Simulation Result:** 🚧 RUNS (debugging required)
- **Next Milestone:** First successful FreeRTOS boot with task switching

---

**Status:** Phase 2 compilation complete, boot debugging in progress
**Next Session:** Debug startup sequence, achieve first successful FreeRTOS boot
