# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 58, 2025-10-29)

### 🎯 CURRENT PHASE: Phase 2 Optimization - Enhanced FreeRTOS Testing
- **Status**: ✅ **IMEM Data Port Fixed - Strings Loading!** (Session 58)
- **Goal**: Comprehensive FreeRTOS validation before RV64 upgrade
- **Tasks**:
  1. ✅ Basic FreeRTOS boot validated (Session 46)
  2. ✅ Enhanced multitasking demo created (Session 47)
  3. ✅ Queue and sync demos created (Session 47)
  4. ✅ **CLINT mtime prescaler bug FIXED** (Session 48)
  5. ✅ **Trap handler installation verified** (Session 49)
  6. ✅ **Bus 64-bit read extraction FIXED** (Session 51)
  7. ✅ **BUS WAIT STALL FIXED** (Session 52) 🎉
  8. ✅ **MTVEC/STVEC 2-byte alignment FIXED** (Session 53) 🎉
  9. ✅ **xISRStackTop calculation workaround** (Session 53)
  10. ✅ **EX/MEM hold during bus wait FIXED** (Session 54) 🎉
  11. ✅ **FreeRTOS boots and scheduler starts** (Session 55)
  12. ✅ **MSTATUS.FS field fully implemented** (Session 56) 🎉
  13. ✅ **FPU context save DISABLED - workaround applied** (Session 57) 🎉
  14. ✅ **IMEM data port byte-level access FIXED** (Session 58) 🎉
  15. ✅ **FreeRTOS prints startup banner** - strings loading correctly!
  16. 📋 **NEXT**: Debug queue assertion (cycle 30,355)
  17. 📋 Debug illegal instruction at cycle 39,415
  18. 📋 Test FreeRTOS task switching and timer interrupts
  19. 📋 Return to FPU instruction decode issue (deferred)
  20. 📋 Optional: UART interrupt-driven I/O

### 🎉 Session 58 Achievement: IMEM Data Port Fixed - Strings Loading! 🎉
- **Bug Fixed**: Instruction memory halfword alignment broke byte-level data reads
  - Root cause: C extension support added halfword alignment to ALL reads
  - Impact: Startup code .rodata copy failed - strings read as 0x00000013 (NOP)
  - Fix: Added `DATA_PORT` parameter to `instruction_memory` module
    - `DATA_PORT=0`: Halfword-aligned (instruction fetch)
    - `DATA_PORT=1`: Word-aligned (data reads, byte extraction by bus adapter)
- **Result**: ✅ **FreeRTOS startup banner prints correctly!**
  ```
  ========================================
    FreeRTOS Blinky Demo
    Target: RV1 RV32IMAFDC Core
    FreeRTOS Kernel: v11.1.0
    CPU Clock: 50000000 Hz
    Tick Rate: 1000 Hz
  ========================================

  Tasks created s
  ```
- **Testing**: All regression tests pass (14/14), FreeRTOS progresses further
- **Remaining Issues**: Queue assertion, illegal instruction exceptions (investigating)

### 🎉 Session 57 Achievement: FPU Workaround Applied - Major Progress!
- **Workaround Implemented**: Disabled FPU context save/restore to bypass instruction decode bug
  - Set `portasmADDITIONAL_CONTEXT_SIZE = 0` in FreeRTOS port
  - Emptied `portasmSAVE_ADDITIONAL_REGISTERS` macro (removed all FSD instructions)
  - Emptied `portasmRESTORE_ADDITIONAL_REGISTERS` macro (removed all FLD instructions)
  - **Impact**: Tasks cannot use FPU across context switches (single-task FPU only)
- **Result**: ✅ **FreeRTOS now runs 39K+ cycles!** (vs <1K before)
  - Successfully bypasses FLD/FSD crash at PC=0x12E/0x130
  - FreeRTOS kernel code executes
  - Queue operations, task creation progressing
  - ECALL traps working correctly
- **New Issues Discovered**:
  1. **.rodata copy issue**: Strings not loading correctly from IMEM (cycle ~40-200)
     - Expected: "[Task" (0x5B 54 61 73)
     - Actual: 0x00000013 (NOP)
     - IMEM data port reads may be faulty
  2. **Early assertion**: Cycle 1,829 (very early in init)
  3. **Queue assertion**: Cycle 30,355 - overflow check triggers incorrectly
     - queueLength appears to be pointer value instead of length
  4. **Illegal instruction**: Cycle 39,415 - mtval=0x13 (same symptom as FPU bug!)
     - Suggests underlying instruction decode/pipeline corruption issue remains
- **Documentation Created**:
  - `docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md` - Comprehensive tracking document
  - `docs/SESSION_57_FPU_WORKAROUND_APPLIED.md` - Workaround details and analysis

### 🚨 Deferred Issue: FPU Instruction Decode Bug (Session 56-57)
- **Root Cause**: Unknown - FLD instructions cause illegal instruction exceptions
- **Symptom**: mtval shows wrong instruction (0x13 instead of 0x2002)
- **Hypothesis**: RVC decoder expansion or pipeline corruption bug
- **Status**: Deferred - workaround applied to unblock FreeRTOS testing
- **Investigation Plan**: See `docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md`
- **Priority**: Medium-High - blocks full RV32IMAFDC multitasking support

### 🎉 Session 54 Milestone: EX/MEM Hold Fix (Validated in Session 55)
- **EX/MEM Hold During Bus Wait Bug FIXED**: ✅
  - Root cause: EX/MEM register advanced during bus wait stalls, losing write data
  - Fixed: Added `bus_wait_stall` to `hold_exmem` condition
  - Impact: Multi-cycle peripheral writes (CLINT, UART, PLIC) now preserve data correctly
  - See: `rtl/core/rv32i_core_pipelined.v` lines 277-282
  - **Validation**: Confirmed correct in Session 55 investigation
- **Complete Multi-Cycle Write Fix** (3 parts):
  1. Session 52: Bus wait stall logic (PC + IF/ID)
  2. Session 52: `bus_req_valid` persistence via `bus_req_issued` flag
  3. Session 54: EX/MEM register hold during bus wait
- **Status**: Fix is correct, but FreeRTOS crashes before it can be tested

### Compliance & Testing
- **98.8% RV32 Compliance**: 80/81 official tests passing (FENCE.I failing - low priority)
- **Privilege Tests**: 33/34 passing (97%)
- **Quick Regression**: 14/14 tests, ~4s runtime
- **FreeRTOS**: ⚠️ Runs 39K+ cycles with FPU workaround (Session 57), new issues discovered

### Recent Achievements (Session 46-51)
- ✅ **Bus 64-bit read extraction FIXED** (Session 51)
  - Fixed critical bug in simple_bus.v for CLINT register access
  - 32-bit reads from 64-bit peripherals now extract correct portion
  - Address-based extraction (offset +0 vs +4) working correctly
- ✅ **Testbench infrastructure improved** (Session 50)
  - Identified tb_core_pipelined vs tb_soc usage distinction
  - Added comprehensive bus/CLINT debug tracing
- ✅ **FreeRTOS scheduler starts successfully** (Session 49)
  - Verified trap handlers are properly installed
  - Tasks created and scheduler reaches first context switch
- ✅ **CLINT mtime prescaler bug FIXED** (Session 48)
  - Atomic 64-bit reads now work on RV32
  - Timer initialization completes successfully
- ✅ **MULHU forwarding bug FIXED** (Session 46)
- ✅ Enhanced FreeRTOS testing suite created (Session 47)
  - Created 3 new comprehensive demos (enhanced, queue, sync)
- ✅ All regression tests passing (14/14, 80/81 official)

### Previous Achievements
- ✅ FreeRTOS boots successfully, UART output clean
- ✅ BSS fast-clear accelerator (2000x speedup)
- ✅ IMEM on bus (Harvard architecture complete)
- ✅ Pipeline bug fixed (one-shot write pulses)
- ✅ RVC FP decoder (C.FLDSP/C.FSDSP support)

### Active Issues
- ⚠️ FENCE.I test (low priority - self-modifying code)
- ⚠️ picolibc printf() duplication (workaround: use puts())

**For detailed session history, see**: `docs/CHANGELOG.md`

## Test Infrastructure (CRITICAL - USE THIS!)

**Key Resources:**
- `docs/TEST_CATALOG.md` - All 208 tests (127 custom + 81 official)
- `make help` - All available test targets
- `tools/README.md` - Script reference

**Essential Commands:**
```bash
make test-quick           # Quick regression (14 tests in ~7s) ⚡
make help                 # See available commands
make catalog              # Regenerate test catalog
env XLEN=32 ./tools/run_official_tests.sh all  # Full suite
```

**✨ Auto-Rebuild Feature (2025-10-26):**
- **Individual tests auto-rebuild hex files if missing or stale**
- No more "hex file not found" errors after git operations
- Tests detect when source (.s) is newer than hex and rebuild automatically
- Use `make rebuild-hex` for batch smart rebuild (only changed files)
- Use `make rebuild-hex-force` to force rebuild all

**Workflow for Development:**
1. Run `make test-quick` BEFORE changes (baseline)
2. Make your changes
3. Run `make test-quick` AFTER changes (verify)
4. Before committing: Run full test suite
5. **No need to manually rebuild hex files!** Tests auto-rebuild as needed

## Project Structure
```
rv1/
├── docs/           # Design documents
├── rtl/core/       # CPU core modules
├── rtl/memory/     # Memory components
├── tb/             # Testbenches
├── tests/          # Test programs
└── tools/          # Helper scripts
```

## Design Constraints
- **HDL**: Verilog-2001 compatible
- **Simulation**: Icarus Verilog primary
- **XLEN**: Configurable 32-bit (RV32) or 64-bit (RV64)
- **Endianness**: Little-endian

## Implemented Extensions (98.8% Compliance - 80/81 tests)

| Extension | Tests | Instructions | Key Features |
|-----------|-------|--------------|--------------|
| **RV32I** | 41/42 ⚠️ | 47 | Integer ops, load/store, branches (FENCE.I issue) |
| **RV32M** | 8/8 ✅ | 13 | MUL/DIV (32-cycle mult, 64-cycle div) |
| **RV32A** | 10/10 ✅ | 22 | LR/SC, AMO operations (Session 35 fix) |
| **RV32F** | 11/11 ✅ | 26 | Single-precision FP, FMA |
| **RV32D** | 9/9 ✅ | 26 | Double-precision FP, NaN-boxing |
| **RV32C** | 1/1 ✅ | 40 | Compressed instructions (25-30% density) |
| **Zicsr** | - | 6 | CSR instructions |

**Note**: FENCE.I test failing (pre-existing since Session 33, low priority - self-modifying code rarely used)

## Architecture Features

**Pipeline**: 5-stage (IF, ID, EX, MEM, WB)
- Data forwarding, hazard detection
- LR/SC reservation tracking, CSR RAW hazard detection
- Precise exceptions

**Privilege Architecture**: M/S/U modes
- Full trap handling, delegation (M→S via medeleg/mideleg)
- CSRs: mstatus, sstatus, mie, sie, mtvec, stvec, mepc, sepc, mcause, scause, etc.

**Memory Management**: Sv32/Sv39 MMU with 16-entry TLB

**FPU**: Single/double precision, shared 64-bit register file

## Privilege Mode Test Suite

**Status**: 33/34 tests passing (97%)
**Documentation**: `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md`
**Macros**: `tests/asm/include/priv_test_macros.s` (520+ lines, 50+ macros)

| Phase | Status | Tests | Description |
|-------|--------|-------|-------------|
| 1: U-Mode | ✅ 5/5 | M→U/S→U transitions, ECALL, CSR privilege |
| 2: Status Regs | ✅ 5/5 | MRET/SRET state machine, trap handling |
| 3: Interrupt CSRs | ✅ 4/4 | mip/sip/mie/sie, mideleg |
| 4: Exceptions | ✅ 5/8 | EBREAK, ECALL, delegation |
| 5: CSR Edge Cases | ✅ 4/4 | Read-only CSRs, WARL fields |
| 6: Delegation | ✅ 4/4 | Delegation edge cases |
| 7: Stress Tests | ✅ 2/2 | Mode switching, regression |

## Recent Session Summary

**Session 58** (2025-10-29): IMEM Data Port Fixed - Strings Loading! 🎉
- **Goal**: Debug .rodata copy issue where strings read as NOPs from IMEM
- **Root Cause Found**: C extension halfword alignment broke byte-level data reads
  - `instruction_memory` aligned ALL addresses to halfword boundary
  - Data port reads at 0x101 returned mem[0x100:0x103] (wrong 4-byte chunk)
  - Bus adapter byte extraction selected from wrong word
- **Fix Applied**: Added `DATA_PORT` parameter to `instruction_memory.v`
  - Instruction port (DATA_PORT=0): Halfword-aligned for C extension
  - Data port (DATA_PORT=1): Word-aligned for proper byte extraction
- **Result**: ✅ **FreeRTOS startup banner prints correctly!**
  - Strings now load from IMEM: "FreeRTOS Blinky Demo", "RV1 RV32IMAFDC Core", etc.
  - UART output clean and readable
  - All regression tests pass (14/14)
- **Next Issues**: Queue assertion (queueLength=0x800004b8, looks like pointer), illegal instruction
- See: commit 7af994a, `rtl/memory/instruction_memory.v:15`, `rtl/rv_soc.v:277`

**Session 57** (2025-10-29): FPU Workaround Applied - FreeRTOS Progresses! 🎉
- **Goal**: Apply workaround to bypass FPU instruction decode bug and unblock FreeRTOS testing
- **Achievement**: Disabled FPU context save/restore macros in FreeRTOS port
  - Set `portasmADDITIONAL_CONTEXT_SIZE = 0`
  - Emptied `portasmSAVE_ADDITIONAL_REGISTERS` and `portasmRESTORE_ADDITIONAL_REGISTERS`
  - FreeRTOS now runs **39K+ cycles** instead of crashing at <1K cycles
- **Progress**: FreeRTOS kernel executes, queue operations start, ECALL traps work
- **New Issues Found**:
  1. .rodata copy from IMEM not working correctly (strings read as 0x00000013)
  2. Early assertion at cycle 1,829
  3. Queue assertion at cycle 30,355 (overflow check false positive)
  4. Illegal instruction at cycle 39,415 (mtval=0x13 - same symptom as FPU bug!)
- **Documentation**: Created comprehensive tracking docs for FPU issue and workaround
- **Impact**: FPU context switching disabled, but allows FreeRTOS testing to continue
- **Status**: Workaround successful, FPU decode bug deferred for later investigation
- **Next**: Debug .rodata copy issue and IMEM data port reads
- See: `docs/SESSION_57_FPU_WORKAROUND_APPLIED.md`, `docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md`

**Session 56** (2025-10-28): MSTATUS.FS Implementation - Hardware Complete, Decode Issue Found 🎉
- **Goal**: Investigate FPU exception root cause (suspected missing MSTATUS.FS field)
- **Achievement**: Full MSTATUS.FS field implementation (7 changes across 4 files)
  1. Added FS field constants to `rv_csr_defines.vh` (bits [14:13])
  2. Initialize FS=11 (Dirty) on reset in `csr_file.v`
  3. Extract FS field and add output wire
  4. **Critical**: Preserve FS in MSTATUS write handler (was being lost!)
  5. Wire `mstatus_fs` signal from CSR→Core→Control Unit
  6. Add FS validation in control unit (4 FP opcode types)
  7. Enhanced CSR debug output with operation tracking
- **Testing**: ✅ All regression tests pass (14/14), including FPU tests
- **Surprise Discovery**: FreeRTOS DOES initialize MSTATUS.FS!
  - Uses `CSRRS mstatus, 0x2000` to enable FPU (same approach as SiFive fork)
  - Official docs claim no FPU support, but code includes it
  - MSTATUS.FS stays at 11 (Dirty) throughout execution
- **New Mystery**: Exception still occurs despite FS=11!
  - FLD instruction at PC=0x130 should work with FS=11
  - But mtval=0x13 (NOP), not 0x2002 (FLD) - instruction corruption?
  - Control unit never sees OP_LOAD_FP - decode issue?
  - **Hypothesis**: RVC decoder expansion or pipeline corruption, NOT MSTATUS.FS
- **Status**: Hardware implementation complete, but real issue is elsewhere
- **Next**: Debug instruction decode/pipeline (C.FLDSP expansion)
- See: `docs/SESSION_56_FPU_EXCEPTION_ROOT_CAUSE.md`

**Session 55** (2025-10-28): FreeRTOS Crash Investigation - REGRESSION FOUND
- **Goal**: Investigate timer interrupt delivery after Session 54 fix
- **Discovery**: FreeRTOS crashes in main() BEFORE reaching timer setup
  - Never reaches `vTaskStartScheduler()` or `vPortSetupTimerInterrupt()`
  - Crash location: During/after puts() calls in main()
  - UART output: "Taskscreatedsu" (truncated/corrupted)
  - CPU ends up in infinite NOP loop (executing garbage memory)
- **Validation**: Session 54 EX/MEM hold fix confirmed correct
  - Address calculation verified: 0x400800 << 3 = 0x02004000 ✅
  - Fix would work correctly if FreeRTOS reached that code
- **Root Cause**: Unknown - likely stack/memory corruption or return address issue
- **Progress**: Investigation complete, detailed analysis documented
- **Next Session**: Debug main() crash before resuming timer interrupt work
- See: `docs/SESSION_55_FREERTOS_CRASH_INVESTIGATION.md`

**Session 54** (2025-10-28): Hold EX/MEM During Bus Wait - CRITICAL PIPELINE BUG FIXED! 🎉
- **EX/MEM Hold Bug FIXED**: Pipeline register wasn't held during bus wait stalls
  - Root cause: `hold_exmem` didn't include `bus_wait_stall` condition
  - Effect: EX/MEM register advanced during multi-cycle peripheral writes, losing store data
  - Fixed: Added `bus_wait_stall` to `hold_exmem` calculation (rv32i_core_pipelined.v:277-282)
  - Impact: Multi-cycle writes to CLINT/UART/PLIC now preserve data correctly
- **Complete Multi-Cycle Write Fix** (3 parts now working together):
  1. Session 52: Bus wait stall logic (PC + IF/ID stalling)
  2. Session 52: `bus_req_valid` persistence via `bus_req_issued` flag
  3. Session 54: EX/MEM register hold during bus wait ← **This fix!**
- **Progress**: All regression tests passing (14/14), CLINT writes should now complete
- See: `docs/SESSION_54_HOLD_EXMEM_BUS_WAIT_FIX.md`

**Session 53** (2025-10-28): Timer Interrupt Fixes - CRITICAL BUGS FIXED! 🎉
- **MTVEC/STVEC Alignment Bug FIXED**: Trap vectors were forcing 4-byte alignment (incompatible with C extension)
  - Modified csr_file.v to support 2-byte alignment when ENABLE_C_EXT=1
  - Trap handlers now reach correct addresses (e.g., 0x8000005E instead of 0x8000005C)
  - Affects all interrupt and exception handling
- **xISRStackTop Calculation Bug WORKAROUND**: Address calculation resulted in wrong value (0x0000C350 vs 0x80040CE0)
  - Disabled configISR_STACK_SIZE_WORDS to use linker-provided __freertos_irq_stack_top
  - FreeRTOS now reaches vPortSetupTimerInterrupt() successfully
  - Eliminated stack corruption and memset issues
- **Progress**: FreeRTOS boots further than ever - reaches timer setup, generates CLINT accesses
- **Remaining**: CLINT multi-cycle write completion (writes start but don't finish)
- See: `docs/SESSION_53_TIMER_INTERRUPT_FIXES.md`

**Session 52** (2025-10-28): Bus Wait Stall Fix - MAJOR BREAKTHROUGH! 🎉
- Fixed critical pipeline synchronization bug causing PC corruption with slow peripherals
- Root cause: Hazard unit didn't check bus_req_ready, pipeline advanced during pending transactions
- Added bus_wait_stall to halt pipeline when bus_req_valid=1 && bus_req_ready=0
- Modified bus_req_valid to stay high during stalls (via bus_req_issued flag)
- PC corruption eliminated - stores to CLINT/UART/PLIC now work correctly
- All regression tests passing (14/14)
- FreeRTOS now unblocked - ready for testing (Session 53)
- See: `docs/SESSION_52_BUS_WAIT_STALL_FIX.md`

**Session 51** (2025-10-28): Bus 64-bit Read Bug - FIXED! ✅
- Fixed critical bug in simple_bus.v where 32-bit reads from 64-bit CLINT registers returned full value
- Added address-based extraction logic (offset +0 vs +4) for correct 32-bit portion
- All regression tests passing (14/14)
- Discovered next blocker: Pipeline doesn't stall for peripheral ready (fixed in Session 52)
- Created minimal test programs (test_clint_mtimecmp_write, test_clint_read_simple)
- See: `docs/SESSION_51_BUS_FIX.md`

**Session 50** (2025-10-28): Bus Investigation - Testbench Issue Found
- Found testbench mismatch: peripheral tests need tb_soc.sh, not run_test_by_name.sh
- Added comprehensive bus/CLINT debug tracing
- Discovered FreeRTOS MTIMECMP stores don't reach bus (still unsolved)
- See: `docs/SESSION_50_BUS_INVESTIGATION.md`

**Session 49** (2025-10-28): Trap Handler Investigation - Bus Issue Found
- Verified FreeRTOS trap handlers are correctly installed (not stubs)
- Scheduler starts successfully, vPortSetupTimerInterrupt() called
- Found blocker: MTIMECMP writes never reach CLINT peripheral
- See: `docs/SESSION_49_TRAP_HANDLER_INVESTIGATION.md`

**Session 48** (2025-10-28): CLINT MTIME Prescaler Bug - FIXED! 🎉
- Fixed fundamental CLINT design bug preventing atomic 64-bit reads on RV32
- Added MTIME_PRESCALER=10 to increment mtime every 10 cycles (not every cycle)
- FreeRTOS now completes timer initialization successfully
- Discovered next blocker: FreeRTOS trap handlers are stubs (infinite loops)
- Added comprehensive debug infrastructure (CSR, PC, memset, mtime, trap handler tracing)
- See: `docs/SESSION_48_CLINT_MTIME_FIX.md`

**Session 47** (2025-10-28): Enhanced FreeRTOS Testing Suite - CREATED
- Created 3 comprehensive FreeRTOS demos (enhanced multitasking, queue, sync)
- Updated Makefile for multi-demo support
- All demos build successfully
- Discovered scheduler starts but tasks don't execute
- See: `docs/SESSION_47_PHASE_1_4_SUMMARY.md`

**Session 46** (2025-10-28): M-Extension Forwarding Bug - FIXED! 🎉
- Fixed data forwarding bug for M-extension results
- FreeRTOS now boots successfully and starts scheduler
- Added comprehensive multiplier debug tracing
- See: `docs/SESSION_46_MULHU_BUG_FIXED.md`

**Session 45** (2025-10-28): MULHU Bug Root Cause - ISOLATED
- Root cause isolated: MULHU returns operand_a instead of computed result
- Context-specific: Official tests pass, FreeRTOS context fails
- See: `docs/SESSION_45_SUMMARY.md`

**Earlier Sessions**: See `docs/CHANGELOG.md` for complete history (Sessions 1-44)

## Naming Conventions

**Files**: `snake_case.v`, testbenches `tb_<module>.v`
**Signals**: `_n` (active-low), `_r` (registered), `_next` (next-state)
**Parameters**: UPPERCASE with underscores

## Testing Strategy
1. Unit Tests - Each module independently
2. Instruction Tests - Known results verification
3. Compliance Tests - RISC-V official suite (81/81 ✅)
4. Program Tests - Assembly programs (Fibonacci, sorting)
5. Privilege Tests - M/S/U mode coverage

## When Assisting

**Before Changes:**
1. Check `docs/PHASES.md` for current phase
2. Review `docs/ARCHITECTURE.md` for constraints
3. Verify against RISC-V spec
4. Run `make test-quick` for baseline

**Code Style:**
- 2-space indentation, lines <100 chars
- Comment complex logic, meaningful signal names

**Debug Approach:**
1. Check waveforms → 2. Control signals → 3. Instruction decode → 4. Data path → 5. Timing

## Statistics
- **Instructions**: 184+ (I:47, M:13, A:22, F:26, D:26, C:40, Zicsr:6)
- **Official Tests**: 80/81 (98.8%) ⚠️ (FENCE.I failing, low priority)
- **Custom Tests**: 60+ programs
- **Configuration**: RV32/RV64 via XLEN parameter

## References
- RISC-V ISA Spec: https://riscv.org/technical/specifications/
- Test Suite: https://github.com/riscv/riscv-tests
- Compliance: https://github.com/riscv/riscv-compliance

## Known Issues

See `docs/KNOWN_ISSUES.md` for complete tracking and history.

**Low Priority:**
- ⚠️ FENCE.I test (self-modifying code, 80/81 = 98.8%)
- ⚠️ picolibc printf() duplication (workaround: use puts())

## OS Integration Roadmap

**Goal**: Progressive OS validation from embedded RTOS to full Linux (16-24 weeks)
**Documentation**: `docs/OS_INTEGRATION_PLAN.md`, `docs/MEMORY_MAP.md`

**Current**: Phase 2 (FreeRTOS) - ✅ **COMPLETE!** Scheduler running! 🎉

| Phase | Status | Duration | Milestone |
|-------|--------|----------|-----------|
| 1: RV32 Interrupts | ✅ Complete | 2-3 weeks | CLINT, UART, SoC integration |
| 2: FreeRTOS | ✅ Complete | 1-2 weeks | Multitasking RTOS - Scheduler starts! |
| 3: RV64 Upgrade | **Next** | 2-3 weeks | 64-bit, Sv39 MMU |
| 4: xv6-riscv | Pending | 3-5 weeks | Unix-like OS, OpenSBI |
| 5a: Linux nommu | Optional | 3-4 weeks | Embedded Linux |
| 5b: Linux + MMU | Pending | 4-6 weeks | Full Linux boot |

## Future Enhancements

**Current Priority**: Phase 3 - RV64 Upgrade (64-bit support, Sv39 MMU)

**Long-term**:
- Extensions: Bit Manipulation (B), Vector (V), Crypto (K)
- Performance: Branch prediction, caching, out-of-order execution
- System: Debug module, PMP, Hypervisor extension
- Verification: Formal verification, FPGA synthesis, ASIC tape-out
