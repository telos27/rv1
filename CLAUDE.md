# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 84, 2025-11-04)

### 🎯 CURRENT PHASE: Phase 3 - RV64 Upgrade (Day 8)
- **Previous Phase**: ✅ Phase 2 COMPLETE - FreeRTOS fully operational (Session 76)
- **Current Focus**: 🔍 Debugging RV64 memory/bus subsystem (test script was running RV32 tests!)
- **Documentation**: `docs/SESSION_84_RV64A_DEBUG_ANALYSIS.md`

### ⚠️ Phase 3 Status Update (Sessions 77-84)
**CRITICAL DISCOVERY**: Test script bug - reported RV64 results were actually RV32!

- **RV32 Compliance**: 80/81 tests (98.8%) - Genuinely passing ✅
- **RV64 Compliance**: Unknown - test script has been running RV32 tests instead
  - Script hardcodes `rv32` prefix, ignores XLEN environment variable
  - Previous "98% RV64" reports were false positives
  - At least 1 confirmed failing test: rv64ua-p-lrsc

**Session 84 Findings**:
- RV32 lrsc test PASSES, RV64 lrsc test FAILS (same test code)
- Bug is RV64-specific, likely in memory/bus adapter address handling
- Forwarding logic is correct - no pipeline design flaw
- PC trace was misleading (showed MEM stage values, not ID stage values)

### Recent Sessions Summary (Details in docs/SESSION_*.md)

**Session 84** (2025-11-04): Rigorous debug - found test script bug, RV64 memory subsystem issue
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
**Extensions**: RV32IMAFDC (184+ instructions) + Zicsr
**Pipeline**: 5-stage (IF/ID/EX/MEM/WB), data forwarding, hazard detection
**Privilege**: M/S/U modes, trap handling, delegation
**MMU**: Sv32/Sv39 with 16-entry TLB
**FPU**: Single/double precision, NaN-boxing

## Known Issues
- 🔴 **RV64 test script bug**: `run_official_tests.sh` hardcodes rv32, doesn't run actual RV64 tests
- 🔴 **RV64 memory/bus issue**: rv64ua-p-lrsc fails (likely address handling in 64-bit mode)
- ⚠️ FPU instruction decode bug (Sessions 56-57) - context save/restore disabled

## OS Integration Roadmap
| Phase | Status | Milestone |
|-------|--------|-----------|
| 1: RV32 Interrupts | ✅ Complete (2025-10-26) | CLINT, UART, SoC |
| 2: FreeRTOS | ✅ Complete (2025-11-03) | Multitasking RTOS |
| 3: RV64 Upgrade | 🚧 In Progress | 64-bit XLEN, Sv39 MMU |
| 4: xv6-riscv | Pending | Unix-like OS, OpenSBI |
| 5: Linux | Pending | Full Linux boot |

## References
- RISC-V Spec: https://riscv.org/technical/specifications/
- Tests: https://github.com/riscv/riscv-tests
- Docs: `docs/ARCHITECTURE.md`, `docs/PHASES.md`, `docs/TEST_CATALOG.md`
