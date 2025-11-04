# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 85, 2025-11-04)

### 🎯 CURRENT PHASE: Phase 3 - RV64 Upgrade (Day 9) - ✅ COMPLETE!
- **Previous Phase**: ✅ Phase 2 COMPLETE - FreeRTOS fully operational (Session 76)
- **Current Status**: ✅ **RV64 IMA 100% COMPLETE** - True baseline established!
- **Documentation**: `docs/SESSION_85_RV64_TRUE_BASELINE.md`

### ✅ Phase 3 Complete! True RV64 Results (Session 85)
**MAJOR BREAKTHROUGH**: Fixed test script bug, established true RV64 baseline!

- **RV32 Compliance**: 80/81 tests (98.8%) ✅
- **RV64 Compliance**: 91/106 tests (85.8%) ✅
  - **RV64I**: 49/50 (98%) - Only FENCE.I fails ✅
  - **RV64M**: 13/13 (100%) - Perfect multiply/divide ✅
  - **RV64A**: 19/19 (100%) - **lrsc passes!** (was false negative) ✅
  - **RV64F**: 4/11 (36%) - FPU issues (pre-existing)
  - **RV64D**: 6/12 (50%) - FPU issues (pre-existing)
  - **RV64C**: 0/1 (0%) - Timeout (low priority)

**Session 85 Fixes**:
- Test script now respects XLEN environment variable
- Added RV64 test compilation (106 tests)
- rv64ua-p-lrsc PASSES (previous failure was false negative)
- **RV64 IMA core is production-ready for Phase 4!**

### Recent Sessions Summary (Details in docs/SESSION_*.md)

**Session 85** (2025-11-04): ✅ Fixed test script, RV64 IMA 100%! (91/106 total, 85.8%)
**Session 84** (2025-11-04): Discovered test script bug (ran RV32 tests instead of RV64)
**Session 83** (2025-11-04): RV64A LR/SC investigation - SC hardware verified correct
**Session 82** (2025-11-03): RV64M/A progress (note: test results invalid due to script bug)
**Session 81** (2025-11-03): RV64I 98.1% complete (data memory + word shift fixes)
**Session 80** (2025-11-03): RV64 test infrastructure setup (40/54 initial pass)
**Session 79** (2025-11-03): RV64 testbench bus interface fix (LD/LWU/SD working)
**Session 78** (2025-11-03): RV64I word operations + SRAIW fix (9 operations validated)
**Session 77** (2025-11-03): Phase 3 start - RV64 config, audit (70% RV64-ready)
**Session 76** (2025-11-03): Phase 2 COMPLETE - FreeRTOS fully operational!

### Critical Bug Fixes (Phase 2-3)
**Phase 2** (Sessions 62-76):
- MRET/Exception Priority (62, 74): Prevented PC corruption
- C Extension Config (66): Enabled compressed instructions at 2-byte boundaries
- CLINT Bus Interface (75): Fixed req_ready timing for timer interrupts
- MSTATUS.MIE Restoration (76): Force MIE=1 on context restore

**Phase 3** (Sessions 77-82):
- RV64 testbench bus interface (79): Connected dmem_bus_adapter
- Data memory loading (81): Added MEM_FILE parameter
- Word shift operations (81): Mask shift amount to 5 bits for word ops
- SRAIW sign-extension (78): Sign-extend operand A for arithmetic shifts
- RV64M/A bugs (82): 7 fixes (op_width, masking, comparisons, sign-ext)

See `docs/SESSION_*.md` for complete history

## Test Infrastructure
**Commands**: `make test-quick` (14 tests, ~4s), `make help`, `env XLEN=32 ./tools/run_official_tests.sh all`
**Resources**: `docs/TEST_CATALOG.md` (208 tests), `tools/README.md`
**Workflow**: Run `make test-quick` before/after changes

## Implemented Extensions & Architecture
**RV32 Compliance**: 80/81 tests (98.8%), FENCE.I fails (low priority)
**RV64 Compliance**: 91/106 tests (85.8%), RV64 IMA 100% complete!
**Extensions**: RV32/RV64 IMAFDC (200+ instructions) + Zicsr
**Pipeline**: 5-stage (IF/ID/EX/MEM/WB), data forwarding, hazard detection
**Privilege**: M/S/U modes, trap handling, delegation
**MMU**: Sv32/Sv39 with 16-entry TLB
**FPU**: Single/double precision, NaN-boxing

## Known Issues
- ⚠️ FPU issues (13 failing tests in RV64F/D, pre-existing from Sessions 56-57)
- ⚠️ RV64C timeout (1 test, low priority)
- ⚠️ FENCE.I fails (both RV32/RV64, by design - not implemented)

## OS Integration Roadmap
| Phase | Status | Milestone |
|-------|--------|-----------|
| 1: RV32 Interrupts | ✅ Complete (2025-10-26) | CLINT, UART, SoC |
| 2: FreeRTOS | ✅ Complete (2025-11-03) | Multitasking RTOS |
| 3: RV64 Upgrade | ✅ Complete (2025-11-04) | RV64 IMA 100%, Sv39 MMU |
| 4: xv6-riscv | 🎯 Next | Unix-like OS, OpenSBI |
| 5: Linux | Pending | Full Linux boot |

## References
- RISC-V Spec: https://riscv.org/technical/specifications/
- Tests: https://github.com/riscv/riscv-tests
- Docs: `docs/ARCHITECTURE.md`, `docs/PHASES.md`, `docs/TEST_CATALOG.md`
