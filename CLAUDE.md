# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 67, 2025-10-29)

### 🎯 CURRENT PHASE: Phase 2 - FreeRTOS Debugging
- **Status**: ⚠️ **FreeRTOS prints banner but crashes at scheduler start** - Two critical bugs fixed!
- **Goal**: Comprehensive FreeRTOS validation before RV64 upgrade
- **Major Milestones**:
  - ✅ MRET/exception priority bug FIXED (Session 62) 🎉
  - ✅ FreeRTOS scheduler RUNNING - 500K+ cycles! 🎉
  - ✅ CPU hardware fully validated (Sessions 62-63)
  - ✅ Stack initialization verified CORRECT (Session 64)
  - ✅ Pipeline flush logic validated CORRECT (Session 65) 🎉
  - ✅ C extension config bug FIXED (Session 66) 🎉
  - ✅ **Testbench false positive FIXED (Session 67)** - Assertion watchpoint corrected! 🎉
  - ✅ **FreeRTOS FPU binary rebuilt (Session 67)** - Stale binary replaced! 🎉
  - 📋 **NEXT**: Debug scheduler crash at xPortStartFirstTask (PC → 0xa5a5a5XX)

### Latest Sessions (67, 66, 65, 64, 63-corrected)

**Session 67** (2025-10-29): Testbench False Positive & FPU Binary Fixed! 🎉🎉
- **Bug #1 - Testbench**: Assertion watchpoint at wrong address (0x1c8c instead of 0x23e8)
  - Caused false positive at cycle 33,569 terminating simulation prematurely
  - Fixed: Updated `tb/integration/tb_freertos.v:792` to use correct address
  - Result: Simulation runs full 500K cycles (15x improvement)
- **Bug #2 - Stale Binary**: FreeRTOS compiled with FPU context save despite Session 57 workaround
  - xPortStartFirstTask had FPU instructions causing illegal instruction loop
  - Root cause: Binary compiled BEFORE workaround source code changes
  - Fixed: Rebuilt FreeRTOS (`make clean && make`), FPU instructions now removed
  - Result: No more FPU exceptions, prints full banner via UART
- **Current Issue**: FreeRTOS crashes after "Starting FreeRTOS scheduler..." (PC → 0xa5a5a5XX)
- **Status**: Major progress (2 bugs fixed), new crash exposed (stack/context issue)
- See: `docs/SESSION_67_TESTBENCH_FALSE_POSITIVE_AND_FPU_REBUILD.md`

**Session 66** (2025-10-29): C Extension Misalignment Bug FIXED! 🎉🎉🎉
- **Root Cause**: `CONFIG_RV32I` in rv_config.vh forcibly disabled ENABLE_C_EXT, overriding command-line `-DENABLE_C_EXT=1`
- **Impact**: Caused instruction address misalignment exceptions for 2-byte aligned addresses (0x0e, 0x200e, etc.)
- **Fix**: Modified rv_config.vh to respect command-line overrides using `ifndef` guards
- **Result**: Compressed instructions (RET, C.JR, etc.) now execute correctly at 2-byte boundaries
- **Verification**: 14/14 quick regression tests PASS, FreeRTOS runs 22K+ cycles (vs 500K before)
- **Status**: Critical bug fixed, but FreeRTOS still has infinite loop (different issue)
- See: `docs/SESSION_66_C_EXTENSION_MISALIGNMENT_BUG_FIXED.md`

**Session 65** (2025-10-29): Pipeline Flush Investigation - Hardware Validated! ✅
- **Goal**: Investigate if pipeline flush logic causes JAL/JALR to fail
- **Discovery**: ✅ **Pipeline flush logic is CORRECT!**
- **Investigation Process**:
  1. Attempted "fix": Remove `ex_take_branch` from `flush_idex`
  2. Result: FreeRTOS ran longer BUT broke atomic/RVC tests (2/14 failed)
  3. Analysis: "Fix" allowed wrong-path instructions to execute (incorrect)
  4. Validation: Original code passes all regression tests (14/14) ✅
- **Key Findings**:
  - Branch/jump instructions flush correctly via `ex_take_branch` in both `flush_ifid` and `flush_idex`
  - EX/MEM latches branch instruction BEFORE ID/EX flush happens (Verilog timing)
  - Branch completes through MEM→WB and writes return address correctly ✅
  - Removing `ex_take_branch` from `flush_idex` is WRONG - allows wrong-path execution
- **FreeRTOS Issues**: NOT caused by pipeline logic, need software-level investigation
- **Status**: CPU hardware fully validated, pipeline logic correct
- See: `docs/SESSION_65_PIPELINE_FLUSH_INVESTIGATION.md`

**Session 64** (2025-10-29): Stack Initialization Investigation ⚠️
- **Discovery**: Session 63's conclusion was WRONG! Stack initialization IS working correctly
- **Investigation**: Memory write watchpoints traced all writes to Task B's stack
- **Key Findings**:
  - ✅ `pxPortInitialiseStack()` working correctly - writes ra=0 at cycle 14945
  - ✅ ra=0 is CORRECT per FreeRTOS design (`configTASK_RETURN_ADDRESS = 0`)
  - ✅ No stack corruption - value stays 0x00000000 after initialization
  - ❌ Session 63 misdiagnosed correct behavior as "uninitialized"
- **CPU Status**: ✅ All hardware validated (MRET, pipeline, CSRs, trap handling, stack init)
- **Real Bug**: NOT stack initialization! Possible causes:
  1. JAL/JALR not writing return addresses correctly
  2. Register file forwarding bug (ra writes lost)
  3. Trap handler context save/restore corrupting ra
  4. Different root cause entirely
- **Next**: Test JAL/JALR execution, register file writes, trap handler
- See: `docs/SESSION_64_STACK_INITIALIZATION_INVESTIGATION.md`

**Session 63** (2025-10-29): Context Switch Investigation - CONCLUSION REVISED ⚠️
- **Original Conclusion** (INCORRECT): Task stacks uninitialized
- **Correction** (Session 64): Stack IS initialized correctly, ra=0 is expected value
- **Still Valid**: Session 62 MRET fix correct, CPU hardware validated, crash trace analysis
- See: `docs/SESSION_63_FREERTOS_CONTEXT_SWITCH_BUG.md` (with correction notice)

**Session 62** (2025-10-29): MRET/Exception Priority Bug FIXED 🎉🎉🎉
- **Root Cause**: When MRET flushed pipeline, `trap_entry` to CSR bypassed priority check, corrupting MEPC
- **Fix**: Changed `.trap_entry(exception_gated)` to `.trap_entry(trap_flush)` (rv32i_core_pipelined.v:1633)
- **Result**: FreeRTOS runs 500,000+ cycles (12.7x improvement), scheduler working!
- **Impact**: Session 57's "FPU workaround" no longer needed - can re-enable FPU context save
- See: `docs/SESSION_62_MRET_EXCEPTION_PRIORITY_BUG_FIXED.md`

### Key Bug Fixes (Sessions 46-67)
- ✅ Testbench false positive (Session 67) - CRITICAL fix: assertion watchpoint at wrong address
- ✅ Stale FreeRTOS binary (Session 67) - CRITICAL fix: rebuilt with FPU disabled
- ✅ C extension config bug (Session 66) - CRITICAL fix enabling compressed instructions at 2-byte boundaries
- ✅ MRET/exception priority bug (Session 62) - CRITICAL fix enabling FreeRTOS scheduler
- ✅ M-extension operand latch bug (Session 60) - Back-to-back M-instructions now work
- ✅ Debug infrastructure built (Session 59) - Call stack, watchpoints, register monitoring
- ✅ IMEM data port byte-level access (Session 58) - Strings load correctly
- ✅ MSTATUS.FS field fully implemented (Session 56) - FPU permission checking
- ✅ EX/MEM hold during bus wait (Session 54) - Multi-cycle peripheral writes preserved
- ✅ MTVEC/STVEC 2-byte alignment (Session 53) - C extension compatibility
- ✅ Bus wait stall logic (Session 52) - Pipeline sync with slow peripherals
- ✅ Bus 64-bit read extraction (Session 51) - CLINT register access
- ✅ CLINT mtime prescaler (Session 48) - Atomic 64-bit reads on RV32
- ✅ M-extension forwarding (Session 46) - MULHU data forwarding

**For complete session history, see**: `docs/SESSION_*.md` files

## Compliance & Testing
- **98.8% RV32 Compliance**: 80/81 official tests passing (FENCE.I low priority)
- **Privilege Tests**: 33/34 passing (97%)
- **Quick Regression**: 14/14 tests, ~4s runtime
- **FreeRTOS**: Prints banner (198 chars via UART), crashes at scheduler start (PC → 0xa5a5a5XX)

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

**✨ Auto-Rebuild Feature:**
- Individual tests auto-rebuild hex files if missing or stale
- Tests detect when source (.s) is newer than hex and rebuild automatically
- Use `make rebuild-hex` for batch smart rebuild (only changed files)

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
| **RV32A** | 10/10 ✅ | 22 | LR/SC, AMO operations |
| **RV32F** | 11/11 ✅ | 26 | Single-precision FP, FMA |
| **RV32D** | 9/9 ✅ | 26 | Double-precision FP, NaN-boxing |
| **RV32C** | 1/1 ✅ | 40 | Compressed instructions (25-30% density) |
| **Zicsr** | - | 6 | CSR instructions |

**Note**: FENCE.I test failing (pre-existing since Session 33, low priority)

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

## Naming Conventions

**Files**: `snake_case.v`, testbenches `tb_<module>.v`
**Signals**: `_n` (active-low), `_r` (registered), `_next` (next-state)
**Parameters**: UPPERCASE with underscores

## Testing Strategy
1. Unit Tests - Each module independently
2. Instruction Tests - Known results verification
3. Compliance Tests - RISC-V official suite (80/81 ✅)
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

**Current:**
- ⚠️ FreeRTOS scheduler crash (Session 67) - PC jumps to 0xa5a5a5XX after "Starting scheduler..."
- ⚠️ FPU instruction decode bug (Session 56-57) - FPU context save/restore disabled as workaround

**Low Priority:**
- ⚠️ FENCE.I test (self-modifying code, 80/81 = 98.8%)
- ⚠️ picolibc printf() duplication (workaround: use puts())

## OS Integration Roadmap

**Goal**: Progressive OS validation from embedded RTOS to full Linux (16-24 weeks)
**Documentation**: `docs/OS_INTEGRATION_PLAN.md`, `docs/MEMORY_MAP.md`

**Current**: Phase 2 (FreeRTOS) - Debugging crash (scheduler runs 500K+ cycles)

| Phase | Status | Duration | Milestone |
|-------|--------|----------|-----------|
| 1: RV32 Interrupts | ✅ Complete | 2-3 weeks | CLINT, UART, SoC integration |
| 2: FreeRTOS | 🔄 Debug | 1-2 weeks | Multitasking RTOS - Scheduler runs! |
| 3: RV64 Upgrade | **Next** | 2-3 weeks | 64-bit, Sv39 MMU |
| 4: xv6-riscv | Pending | 3-5 weeks | Unix-like OS, OpenSBI |
| 5a: Linux nommu | Optional | 3-4 weeks | Embedded Linux |
| 5b: Linux + MMU | Pending | 4-6 weeks | Full Linux boot |

## Future Enhancements

**Current Priority**: Complete Phase 2 (FreeRTOS), then Phase 3 (RV64 Upgrade)

**Long-term**:
- Extensions: Bit Manipulation (B), Vector (V), Crypto (K)
- Performance: Branch prediction, caching, out-of-order execution
- System: Debug module, PMP, Hypervisor extension
- Verification: Formal verification, FPGA synthesis, ASIC tape-out
