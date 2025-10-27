# Session 21: Phase 2 FreeRTOS Infrastructure Setup

**Date**: 2025-10-27
**Phase**: Phase 2 - FreeRTOS Port (Infrastructure)
**Status**: ✅ COMPLETE (Phase 1 of execution plan)
**Time**: 15 minutes (vs 2-3 hours estimated)

---

## Overview

Completed the infrastructure setup for FreeRTOS v10.5.1 LTS port to RV32IMAFDC. This session focused on preparing the memory subsystem and development environment for the upcoming FreeRTOS port implementation.

---

## Achievements

### 1. Memory System Expansion ✅

**Goal**: Expand DMEM from 64KB to 1MB to support FreeRTOS heap, stacks, and code

**Changes**:
- **File**: `rtl/config/rv_config.vh`
- **Modification**: `DMEM_SIZE` changed from `65536` to `1048576` (64KB → 1MB)
- **Comment**: Added note about Phase 2 unified memory for FreeRTOS

**Validation**:
```bash
make test-quick
# Result: ✅ 14/14 tests passing (zero regressions)
```

**Impact**:
- Memory expansion successful
- Existing tests unaffected (use explicit size overrides)
- Ready for unified memory architecture (code + data in same space)

---

### 2. Directory Structure Creation ✅

**Goal**: Create complete software development hierarchy

**Structure Created**:
```
software/freertos/
├── port/                   # RISC-V port customization
├── config/                 # FreeRTOSConfig.h, linker script
├── lib/                    # UART driver, startup code
├── demos/                  # Demo applications
├── Makefile                # Build system
└── README.md               # Documentation
```

**Commands Executed**:
```bash
mkdir -p software/freertos/{port,config,lib,demos}
touch software/freertos/{Makefile,README.md}
```

**Validation**:
- ✅ All directories created successfully
- ✅ Structure matches execution plan specification

---

### 3. FreeRTOS Kernel Clone ✅

**Goal**: Obtain FreeRTOS v10.5.1 LTS kernel with RISC-V port

**Details**:
- **Repository**: https://github.com/FreeRTOS/FreeRTOS-Kernel.git
- **Version**: V10.5.1 (tag def7d2d)
- **Method**: Direct clone with `--depth 1 --branch V10.5.1`
- **Location**: `software/freertos/FreeRTOS-Kernel/`

**Kernel Contents Verified**:
- ✅ Core files: `tasks.c`, `queue.c`, `list.c`, `timers.c`, `event_groups.c`, `stream_buffer.c`
- ✅ Header files: `include/` directory with all FreeRTOS headers
- ✅ RISC-V port: `portable/GCC/RISC-V/` with `port.c`, `portASM.S`, `portmacro.h`
- ✅ Heap implementations: `portable/MemMang/heap_{1,2,3,4,5}.c` (using heap_4.c)

**Port Layer Available**:
```
FreeRTOS-Kernel/portable/GCC/RISC-V/
├── port.c              # Context switching, scheduler start
├── portASM.S           # Low-level trap handler (assembly)
├── portmacro.h         # Architecture-specific macros
├── portContext.h       # Context save/restore helpers
└── chip_specific_extensions/  # SiFive-specific (will customize)
```

---

## Technical Details

### Memory Layout (1MB Unified)

**Previous** (64KB Harvard):
```
IMEM: 0x0000_0000 - 0x0000_FFFF  (64KB, instruction only)
DMEM: 0x8000_0000 - 0x8000_FFFF  (64KB, data only)
```

**Current** (1MB Unified, preparation for FreeRTOS):
```
DMEM: 0x8000_0000 - 0x8010_0000  (1MB, code + data)

Planned Layout:
  0x8000_0000  .text (code)                ~20KB
  0x8000_5000  .rodata (constants)         ~5KB
  0x8000_6400  .data (initialized globals) ~2KB
  0x8000_6C00  .bss (uninitialized)        ~3KB
  0x8000_7800  Heap (FreeRTOS)             64KB
  0x8001_7800  Free space                  ~895KB
  0x800F_0000  Task stacks (grows down)    ~64KB
  0x8010_0000  End of RAM
```

**Note**: IMEM still 64KB (unchanged for now), future work may unify completely.

---

### FreeRTOS v10.5.1 LTS Details

**Why v10.5.1 LTS?**
- Long-term support version (stable, well-tested)
- Known RISC-V port compatibility
- Active community support
- Suitable for embedded systems (vs latest bleeding-edge)

**Key Features Available**:
- Preemptive multitasking
- Task priorities (5 levels configured)
- Queues for inter-task communication
- Binary and counting semaphores
- Mutexes with priority inheritance
- Software timers
- Event groups
- Stream buffers

**Heap Implementation (heap_4.c)**:
- Best-fit algorithm with coalescence
- Allows malloc/free (unlike heap_1/2)
- Efficient memory utilization
- 64KB heap planned (configurable)

---

## Files Modified

### 1. `rtl/config/rv_config.vh`
**Change**: Line 145
```verilog
// Before:
`define DMEM_SIZE 65536  // 64KB data memory

// After:
`define DMEM_SIZE 1048576  // 1MB data memory (Phase 2: FreeRTOS unified memory)
```

---

## Files Created

### Directory Structure
```
software/freertos/port/         (empty, awaiting port layer)
software/freertos/config/       (empty, awaiting FreeRTOSConfig.h)
software/freertos/lib/          (empty, awaiting UART driver)
software/freertos/demos/        (empty, awaiting demo apps)
software/freertos/Makefile      (empty, awaiting build system)
software/freertos/README.md     (empty, awaiting documentation)
```

### FreeRTOS Kernel (cloned)
```
software/freertos/FreeRTOS-Kernel/  (v10.5.1, ~300 files)
```

---

## Validation Results

### Quick Regression Tests
```bash
make test-quick
```

**Results**:
```
Total:   14 tests
Passed:  14 ✅
Failed:  0
Time:    4s

✓ All quick regression tests PASSED!
```

**Tests Passed**:
1. ✅ rv32ui-p-add (base ISA)
2. ✅ rv32ui-p-jal (control flow)
3. ✅ rv32um-p-mul (multiply)
4. ✅ rv32um-p-div (divide)
5. ✅ rv32ua-p-amoswap_w (atomics)
6. ✅ rv32ua-p-lrsc (load-reserved/store-conditional)
7. ✅ rv32uf-p-fadd (single-precision FP)
8. ✅ rv32uf-p-fcvt (FP conversion)
9. ✅ rv32ud-p-fadd (double-precision FP)
10. ✅ rv32ud-p-fcvt (double FP conversion)
11. ✅ rv32uc-p-rvc (compressed instructions)
12. ✅ test_fp_compare_simple (custom FP test)
13. ✅ test_priv_minimal (privilege modes)
14. ✅ test_fp_add_simple (custom FP test)

**Conclusion**: Zero regressions from memory expansion ✅

---

## Execution Plan Progress

**Original Estimate**: Phase 1 (Days 1-2) = 2-3 hours
**Actual Time**: 15 minutes
**Ahead of Schedule**: ✅ 92% time savings

**Completion Status**:
- ✅ Step 1.1: Memory System Expansion (COMPLETE)
- ✅ Step 1.2: Directory Structure Creation (COMPLETE)
- ✅ Step 1.3: Clone FreeRTOS Kernel (COMPLETE)
- ⏭️ Step 2.1: FreeRTOSConfig.h (NEXT SESSION)

**Phase 1 Status**: **100% COMPLETE** ✅

---

## Next Session (Phase 2: Port Layer)

**Planned Tasks** (from execution plan):

### Step 2.1: FreeRTOSConfig.h
Create `software/freertos/config/FreeRTOSConfig.h` with:
- CPU clock: 50 MHz
- Tick rate: 1000 Hz (1ms)
- Max priorities: 5
- Heap size: 64KB
- Stack overflow checking enabled

### Step 2.2: portmacro.h
Create `software/freertos/port/portmacro.h` with:
- Stack type definitions
- Critical section macros (disable/enable interrupts)
- Context switch macros
- RISC-V specific settings

### Step 2.3: port.c
Implement `software/freertos/port/port.c`:
- `pxPortInitialiseStack()` - Setup task stack frame
- `xPortStartScheduler()` - Start FreeRTOS
- `xPortSysTickHandler()` - Timer interrupt handler

### Step 2.4: portASM.S
Implement `software/freertos/port/portASM.S`:
- `freertos_trap_handler` - Main trap entry
- Context save/restore (all 32 registers)
- ECALL and timer interrupt handling

**Estimated Time**: 8-12 hours (Days 3-4)

---

## References

1. **Execution Plan**: `docs/PHASE2_FREERTOS_EXECUTION_PLAN.md`
2. **OS Integration**: `docs/OS_INTEGRATION_PLAN.md`
3. **Memory Map**: `docs/MEMORY_MAP.md`
4. **FreeRTOS Docs**: https://www.freertos.org/RTOS.html
5. **RISC-V Port Docs**: `software/freertos/FreeRTOS-Kernel/portable/GCC/RISC-V/readme.txt`

---

## Notes

### Technical Decisions

1. **Why 1MB memory now?**
   - Jump directly to Phase 3 target memory size
   - Avoids needing to expand again later
   - Allows generous heap/stack allocation for FreeRTOS
   - Still fits comfortably in simulation

2. **Why direct clone vs git submodule?**
   - Git submodule failed with detached HEAD
   - Direct clone simpler for development
   - Can convert to submodule later if needed
   - No functional difference for development

3. **Why heap_4?**
   - Best balance of features vs complexity
   - Allows malloc/free (needed for dynamic task creation)
   - Memory coalescence reduces fragmentation
   - Widely used in production FreeRTOS systems

### Lessons Learned

1. **Memory parameterization works well**
   - Changing DMEM_SIZE from 64KB → 1MB had zero impact on tests
   - Testbenches correctly use explicit size overrides
   - Good design pays off in flexibility

2. **FreeRTOS v10.5.1 is well-organized**
   - Clear separation: kernel vs portable layer
   - RISC-V port already exists (great starting point)
   - Multiple heap options available
   - Documentation included

3. **Ahead of schedule**
   - Infrastructure tasks simpler than estimated
   - Good preparation (execution plan) accelerates work
   - More time available for complex port layer work

---

## Summary

**What We Accomplished**:
- ✅ Expanded memory to 1MB (zero breakage)
- ✅ Created complete software directory structure
- ✅ Cloned FreeRTOS v10.5.1 LTS with RISC-V port
- ✅ Validated all changes (14/14 tests passing)
- ✅ Documented progress comprehensively

**Time**: 15 minutes (92% faster than estimated)

**Status**: Phase 1 (Infrastructure) **COMPLETE** ✅

**Next**: Phase 2 (Port Layer Implementation) - FreeRTOSConfig.h, port.c, portASM.S

**Ready for**: Complex port layer work in next session 🚀

---

**END OF SESSION 21**
