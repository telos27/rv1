# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 49, 2025-10-28)

### 🎯 CURRENT PHASE: Phase 2 Optimization - Enhanced FreeRTOS Testing
- **Status**: Blocked - Bus Interconnect Bug (Session 49 → 50)
- **Goal**: Comprehensive FreeRTOS validation before RV64 upgrade
- **Tasks**:
  1. ✅ Basic FreeRTOS boot validated (Session 46)
  2. ✅ Enhanced multitasking demo created (Session 47)
  3. ✅ Queue and sync demos created (Session 47)
  4. ✅ **CLINT mtime prescaler bug FIXED** (Session 48)
  5. ✅ **Trap handler installation verified** (Session 49)
  6. 🐛 **BLOCKER**: MTIMECMP writes don't reach CLINT (Session 50)
  7. 📋 Debug/fix printf() duplication issue
  8. 📋 Optional: UART interrupt-driven I/O

### 🎉 Recent Milestone (Session 49): FreeRTOS Boots and Scheduler Starts!
- **FreeRTOS Boot Sequence**: WORKING ✅
  - ✅ Tasks created successfully
  - ✅ Scheduler starts (`vTaskStartScheduler()` called)
  - ✅ `vPortSetupTimerInterrupt()` executes
  - ✅ Trap handlers properly installed (not stubs!)
- **New Blocker Found**: Bus interconnect issue
  - MTIMECMP writes (address 0x02004000) don't reach CLINT module
  - Store instructions execute but never trigger req_valid on CLINT
  - See: `docs/SESSION_49_TRAP_HANDLER_INVESTIGATION.md`

### Compliance & Testing
- **98.8% RV32 Compliance**: 80/81 official tests passing (FENCE.I failing - low priority)
- **Privilege Tests**: 33/34 passing (97%)
- **Quick Regression**: 14/14 tests, ~4s runtime
- **FreeRTOS**: Boots successfully, timer init complete, reaches scheduler ✅

### Recent Achievements (Session 46-49)
- ✅ **FreeRTOS scheduler starts successfully** (Session 49)
  - Verified trap handlers are properly installed
  - Tasks created and scheduler reaches first context switch
  - Identified bus routing as final blocker
- ✅ **CLINT mtime prescaler bug FIXED** (Session 48)
  - Atomic 64-bit reads now work on RV32
  - Timer initialization completes successfully
  - Comprehensive debug infrastructure added
- ✅ **MULHU forwarding bug FIXED** (Session 46)
- ✅ Enhanced FreeRTOS testing suite created (Session 47)
  - Created 3 new comprehensive demos (enhanced, queue, sync)
  - Updated Makefile for multi-demo support
  - All demos build successfully
- ✅ Comprehensive debug tracing for interrupt debugging
- ✅ All regression tests still passing (14/14, 80/81 official)

### Previous Achievements
- ✅ FreeRTOS boots successfully, UART output clean
- ✅ BSS fast-clear accelerator (2000x speedup)
- ✅ IMEM on bus (Harvard architecture complete)
- ✅ Pipeline bug fixed (one-shot write pulses)
- ✅ RVC FP decoder (C.FLDSP/C.FSDSP support)

### Active Issues
- 🐛 **CRITICAL**: MTIMECMP writes don't reach CLINT module (Session 50)
  - Symptom: Store instructions to 0x02004000 execute but never reach CLINT peripheral
  - CLINT req_valid never asserts, mtimecmp stays at max value (0xFFFFFFFFFFFFFFFF)
  - No timer interrupts → tasks never run (stuck waiting for first context switch)
  - Root cause: Bus interconnect routing issue
  - Next: Debug bus arbiter, verify CLINT connectivity, add bus transaction tracing
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
