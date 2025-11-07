# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 111, 2025-11-06)

### 🎯 CURRENT PHASE: Phase 4 Prep - Memory Subsystem FPGA/ASIC Hardening
- **Previous Phase**: ✅ Phase 3 COMPLETE - 100% RV32/RV64 compliance! (Session 87)
- **Current Status**: 🎉 **REGISTERED MEMORY IMPLEMENTED!** - Memory subsystem now matches FPGA BRAM and ASIC SRAM behavior
- **Git Tag**: `v1.0-rv64-complete` (marks Phase 3 completion)
- **Next Milestone**: `v1.1-xv6-ready` (after fixing VM test timing regressions)
- **Progress**: 9/44 Phase 4 tests passing (20%) - Week 1 at 90% (9/10 tests)

### Session 111: Registered Memory Implementation (2025-11-06)
**Achievement**: ✅ Memory subsystem now matches real hardware! Synchronous registered memory eliminates glitches.

**Key Changes**:
- Changed `data_memory.v` from combinational to synchronous (matches FPGA BRAM/ASIC SRAM)
- Zero performance impact (load-use timing unchanged)
- 700x improvement for VM tests (70 cycles vs 50K+ timeout)
- Files: `rtl/memory/data_memory.v`, `rtl/core/rv32i_core_pipelined.v`

**Status**:
- ✅ Quick regression: 13/14 tests pass (92.9%)
- ✅ Atomic operations: 9/10 official tests pass (90%)
- ⚠️ 3 VM tests regressed (need adjustment for correct 1-cycle memory latency)

**Documentation**: `docs/SESSION_111_REGISTERED_MEMORY_FIX.md` (450 lines with complete FPGA/ASIC analysis)

---

## Recent Critical Bug Fixes (Phase 4 Prep - Sessions 90-111)

### Major Fixes Summary
| Session | Fix | Impact |
|---------|-----|--------|
| **111** | Registered memory (FPGA/ASIC-ready) | 700x improvement, eliminates glitches |
| **110** | EXMEM flush on traps | Prevents infinite exception loops |
| **109** | M-mode MMU bypass | Critical for OS boot |
| **107** | TLB caches faulting translations | 500x improvement |
| **105** | 2-level page table walks | Enables non-identity VM |
| **103** | Page fault pipeline hold | Precise exceptions |
| **100** | MMU in EX stage | Eliminates combinational glitches |
| **94** | SUM permission checking | Critical security fix |
| **92** | Megapage translation | All page sizes work |
| **90** | MMU PTW handshake | VM translation operational |

**Phase 3 Critical Fixes (Sessions 77-89)**:
- Session 87: 100% RV32/RV64 compliance (3 infrastructure bugs fixed)
- Session 86: FPU FMV/conversion fixes (8 tests)
- Sessions 78-85: RV64 word ops, data memory, test infrastructure

**Complete session details**: See `docs/SESSION_*.md` files (50+ detailed session logs)

---

## Test Infrastructure
**Quick Commands**:
- `make test-quick` - 14 regression tests (~4s)
- `env XLEN=32 ./tools/run_official_tests.sh all` - RV32 compliance (187 tests)
- `env XLEN=64 ./tools/run_official_tests.sh all` - RV64 compliance (106 tests)
- `make help` - All available commands

**Documentation**:
- `docs/TEST_CATALOG.md` - Complete test inventory (233 custom + 187 official)
- `docs/PHASE_4_PREP_TEST_PLAN.md` - Phase 4 test plan (44 tests, 4 weeks)
- `tools/README.md` - Test infrastructure details

**Workflow**: Always run `make test-quick` before/after changes to verify zero regressions

---

## Implemented Extensions & Architecture

**Compliance Status**:
- **RV32**: 81/81 tests (100%) ✅ PERFECT!
- **RV64**: 106/106 tests (100%) ✅ PERFECT!

**Extensions**: RV32/RV64 IMAFDC (200+ instructions) + Zicsr + Zifencei

**Architecture**:
- **Pipeline**: 5-stage (IF/ID/EX/MEM/WB), data forwarding, hazard detection
- **Privilege**: M/S/U modes, trap handling, exception delegation
- **MMU**: Sv32/Sv39 with 16-entry TLB, 2-level page table walks
- **FPU**: Single/double precision IEEE 754, NaN-boxing
- **Memory**: Synchronous registered memory (FPGA BRAM/ASIC SRAM compatible)

---

## Known Issues & Next Steps

**Current Issues**:
- ⚠️ 3 VM tests regressed after registered memory fix (timing-sensitive, need adjustment)
- ⚠️ test_tlb_basic_hit_miss fails (SFENCE.VMA timing issue)

**Next Session Tasks**:
1. Fix 3 VM test timing regressions (adjust for 1-cycle memory latency)
2. Fix SFENCE.VMA timing issue
3. Complete Week 1 tests (10/10 passing)
4. Begin Week 2 tests (page fault recovery, syscalls)

---

## OS Integration Roadmap

| Phase | Status | Milestone | Completion |
|-------|--------|-----------|------------|
| 1: RV32 Interrupts | ✅ Complete | CLINT, UART, SoC | 2025-10-26 |
| 2: FreeRTOS | ✅ Complete | Multitasking RTOS | 2025-11-03 |
| 3: RV64 Upgrade | ✅ Complete | **100% RV32/RV64 Compliance** | 2025-11-04 |
| 4: xv6-riscv | 🎯 **In Progress** | Unix-like OS, OpenSBI | TBD |
| 5: Linux | Pending | Full Linux boot | TBD |

**Phase 4 Progress**: 9/44 tests (20%) - Week 1 at 90% (9/10 tests passing)

---

## References & Documentation

**Specifications**:
- RISC-V Spec: https://riscv.org/technical/specifications/
- Official Tests: https://github.com/riscv/riscv-tests

**Project Documentation**:
- `docs/ARCHITECTURE.md` - CPU architecture overview
- `docs/PHASES.md` - Development phases and milestones
- `docs/SESSION_*.md` - Detailed session logs (50+ sessions)
- `docs/PHASE_4_PREP_TEST_PLAN.md` - Current test plan
- `docs/PHASE_4_OS_READINESS_ANALYSIS.md` - Gap analysis for xv6
