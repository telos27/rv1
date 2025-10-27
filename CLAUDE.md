# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status
- **Achievement**: 🎉 **100% COMPLIANCE - 81/81 OFFICIAL TESTS PASSING** 🎉
- **Achievement**: 🎉 **PHASE 1.5 COMPLETE - 6/6 INTERRUPT TESTS PASSING** 🎉
- **Achievement**: 🎉 **FREERTOS BOOTS - SCHEDULER RUNNING** 🎉
- **Achievement**: ⚡ **BSS FAST-CLEAR - 2000x BOOT SPEEDUP** ⚡
- **Target**: RV32IMAFDC / RV64IMAFDC with full privilege architecture
- **Privilege Tests**: 33/34 passing (97%) - Phases 1-2-3-5-6-7 complete, Phase 4: 5/8 ✅
- **OS Integration**: Phase 2 IN PROGRESS 🚧 - FreeRTOS boots, UART output debugging needed
- **Recent Work**: BSS Accelerator & Boot Progress (2025-10-27 Session 24) - See below
- **Session 24 Summary**: Implemented simulation BSS fast-clear, FreeRTOS reaches main() and starts scheduler
- **Next Step**: Session 25 - Debug UART output issue (printf not producing characters)

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

## Implemented Extensions (100% Compliance)

| Extension | Tests | Instructions | Key Features |
|-----------|-------|--------------|--------------|
| **RV32I** | 42/42 ✅ | 47 | Integer ops, load/store, branches, FENCE.I |
| **RV32M** | 8/8 ✅ | 13 | MUL/DIV (32-cycle mult, 64-cycle div) |
| **RV32A** | 10/10 ✅ | 22 | LR/SC, AMO operations |
| **RV32F** | 11/11 ✅ | 26 | Single-precision FP, FMA |
| **RV32D** | 9/9 ✅ | 26 | Double-precision FP, NaN-boxing |
| **RV32C** | 1/1 ✅ | 40 | Compressed instructions (25-30% density) |
| **Zicsr** | - | 6 | CSR instructions |

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

**Documentation**: See `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md`
**Macro Library**: `tests/asm/include/priv_test_macros.s` (520+ lines, 50+ macros)

### Status by Phase

| Phase | Status | Tests | Description |
|-------|--------|-------|-------------|
| 1: U-Mode Fundamentals | ✅ Complete | 5/5 | M→U/S→U transitions, ECALL, CSR privilege |
| 2: Status Registers | ✅ Complete | 5/5 | MRET/SRET state machine, trap handling |
| 3: Interrupt CSRs | ✅ Complete | 4/4 | mip/sip/mie/sie, mideleg (CSR behavior verified) |
| 4: Exception Coverage | ✅ Good | 5/8 | EBREAK, ECALL (all modes), delegation (3 blocked by hardware) |
| 5: CSR Edge Cases | ✅ Complete | 4/4 | Read-only CSRs, WARL fields, side effects, validity |
| 6: Delegation Edge Cases | ✅ Complete | 4/4 | Delegation to current mode, medeleg (writeback gating fixed) |
| 7: Stress & Regression | ✅ Complete | 2/2 | Rapid mode switching, comprehensive regression |

**Progress**: 27/34 tests passing (79%), 7 skipped/documented

### Key Fixes (Recent Sessions)

**Session 24 (2025-10-27)**: BSS Fast-Clear Accelerator & Boot Progress ⚡
- **Achievement**: FreeRTOS boots successfully! main() reached at cycle 95, scheduler starts at cycle 1001
- **Accelerator**: Testbench-only BSS fast-clear saves ~200k cycles (2000x speedup)
- **Implementation**: Detects BSS loop at PC 0x32, clears 260KB in 1 cycle, forces PC to 0x3E
- **Features**: Gated by `ENABLE_BSS_FAST_CLEAR`, validates addresses, displays stats
- **Status**: Boot complete ✅, UART output debugging needed 🚧 (printf produces 0 characters)
- **Reference**: `docs/SESSION_24_BSS_ACCELERATOR.md`

**Session 23 (2025-10-27)**: C Extension Configuration Bug Fix 🐛→✅
- **Bug Found**: FreeRTOS compiled with RVC (compressed instructions), but core simulated without C extension enabled
- **Symptom**: Infinite boot loop with "instruction address misaligned" exceptions (cause=0) at PC 0x1E
- **Root Cause**: 2-byte aligned PCs (e.g., 0x1A after C.LUI) triggered misalignment exception when `ENABLE_C_EXT=0`
- **Investigation**: Systematic debug trace revealed `if_inst_misaligned=1` for valid compressed instruction addresses
- **Fix**: Added `-D ENABLE_C_EXT=1` to `tools/test_freertos.sh` simulation compilation
- **Result**: Boot progresses past FPU initialization, no more trap loops
- **Reference**: Debug testbench `tb/integration/tb_freertos_debug.v` with detailed CSR tracing

**Session 22 (2025-10-27)**: FreeRTOS Compilation & First Boot 🎉
- **Achievement**: FreeRTOS compiled successfully (17KB code, 795KB data) - first RTOS binary!
- **Fixes**: picolibc integration, FreeRTOSConfig.h macros, syscalls cleanup
- **Infrastructure**: `tb_freertos.v`, `test_freertos.sh` created
- **Status**: Compilation ✅, boot debugging needed (stuck at PC 0x14)
- **Reference**: `docs/SESSION_22_SUMMARY.md`

**Session 21 (2025-10-27)**: FreeRTOS Port Layer Complete ✅
- **Achievement**: Full FreeRTOS port for RV32IMAFDC (9 files, 1587 lines)
- **Created**: FreeRTOSConfig.h, start.S, linker script, UART driver, syscalls, Blinky demo
- **FPU Context**: Save/restore all 32 FP registers + FCSR (264 bytes/task)
- **Reference**: `docs/SESSION_21_PHASE_2_SUMMARY.md`

**Session 20 (2025-10-27)**: Phase 1.5 Complete - Interrupt Tests 🎉
- **Achievement**: 6 interrupt tests implemented, all passing (100%)
- **Tests**: MTI/MSI delegation, priority encoding, MIE/SIE masking, nested interrupts
- **Progress**: Privilege tests 33/34 (97%), up from 27/34 (79%)

**Session 19 (2025-10-27)**: Interrupt Delivery & xRET Priority Fix 🔥
- **Critical Fix**: xRET-exception race causing infinite trap loop
- **Solution**: xRET priority over exceptions, interrupt masking during xRET
- **Files**: `rv32i_core_pipelined.v`, `rv_soc.v`, debug infrastructure

**Session 18 (2025-10-27)**: Core Interrupt Handling ⚡
- **Implementation**: Full interrupt detection, priority encoder, delegation logic
- **CSR Ports**: Added mip_out, mie_out, mideleg_out, trap_is_interrupt
- **Priority**: MEI(11) > MSI(3) > MTI(7) > SEI(9) > SSI(1) > STI(5)

**Session 17 (2025-10-27)**: SoC Integration Complete ✅
- **Achievement**: Core connected to bus interconnect, full SoC integration
- **Created**: `dmem_bus_adapter.v`, MMIO test (10 tests passing)
- **Integration**: 4 slaves (CLINT, UART, PLIC, DMEM), interrupt routing complete

**Session 15-16 (2025-10-26/27)**: UART & Bus Interconnect ✅
- **UART**: 16550-compatible (342 lines), 12/12 tests passing
- **Bus**: Simple interconnect (254 lines), priority-based addressing
- **PLIC**: 32 interrupt sources, M/S-mode contexts (390 lines)

**Session 12-14 (2025-10-26)**: CLINT & Phase 3-4 ✅
- **CLINT**: 10/10 tests passing, CSR integration, SoC architecture
- **Phase 3**: Interrupt CSR tests complete (4/4 passing)
- **Phase 4**: Exception coverage analysis, delegation test added

**Session 9-10 (2025-10-26)**: Refactoring Analysis ⚙️
- **Phase 1**: CSR constants extraction (142 lines), config consolidation
- **Phase 2**: Stage extraction analysis - deferred (250+ I/O ports)
- **Decision**: "If it ain't broke, don't fix it" - code well-organized

**Session 7-8 (2025-10-26)**: Writeback Gating & Phase 7 ✅
- **Critical Fix**: Register writes gated by memwb_valid, auto-rebuild infrastructure
- **Phase 7**: Stress tests implemented (rapid switching, comprehensive regression)

**Session 1-6 (2025-10-24 to 2025-10-26)**: Privilege Mode Foundation ✅
- **Phase 5**: CSR edge cases (4/4 tests)
- **Core Fixes**: Exception gating, trap target computation, privilege forwarding
- **Infrastructure**: Trap latency analysis, writeback gating, test auto-rebuild

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
- **Official Tests**: 81/81 (100%) ✅
- **Custom Tests**: 60+ programs
- **Configuration**: RV32/RV64 via XLEN parameter

## References
- RISC-V ISA Spec: https://riscv.org/technical/specifications/
- Test Suite: https://github.com/riscv/riscv-tests
- Compliance: https://github.com/riscv/riscv-compliance

## Known Issues

See `docs/KNOWN_ISSUES.md` for detailed tracking.

**Active:**
- None! All critical issues resolved ✅

**Resolved (Sessions 7-8):**
- ✅ Writeback gating for trap latency - FIXED
- ✅ Hex file management and auto-rebuild - FIXED
- ✅ Phase 7 tests implemented - COMPLETE

## OS Integration Roadmap (NEW! 2025-10-26)

**Goal**: Progressive OS validation from embedded RTOS to full Linux
**Documentation**: See `docs/OS_INTEGRATION_PLAN.md`, `docs/MEMORY_MAP.md`

### Phase 1: RV32 Interrupt Infrastructure (2-3 weeks) 🚧 IN PROGRESS
- **CLINT**: Core-Local Interruptor (timer + software interrupts)
- **UART**: 16550-compatible serial console
- **SoC Integration**: Memory-mapped peripherals, address decoder
- **Tests**: Complete 6 interrupt tests (privilege Phase 3)
- **Milestone**: 34/34 privilege tests passing (100%)

### Phase 2: FreeRTOS (1-2 weeks)
- Port FreeRTOS to RV32IMAFDC
- Demo applications (Blinky, Queue test, UART echo)
- **Milestone**: Multitasking RTOS running

### Phase 3: RV64 Upgrade (2-3 weeks)
- Upgrade XLEN from 32 to 64 bits
- Enhance MMU from Sv32 to Sv39 (3-level page tables)
- Expand memory (1MB IMEM, 4MB DMEM)
- **Milestone**: RV64 compliance (87/87 tests)

### Phase 4: xv6-riscv (3-5 weeks)
- Add PLIC (Platform-Level Interrupt Controller)
- Add block storage (RAM disk initially)
- Integrate OpenSBI firmware (M-mode SBI)
- Port xv6-riscv Unix-like OS
- **Milestone**: xv6 shell, usertests passing

### Phase 5a: Linux nommu (Optional, 3-4 weeks)
- Linux without MMU for embedded targets
- Buildroot rootfs
- **Milestone**: Busybox shell on nommu Linux

### Phase 5b: Linux with MMU (4-6 weeks)
- Full RV64 Linux with Sv39 MMU
- OpenSBI + U-Boot boot flow
- Buildroot with ext2 rootfs
- Optional: Ethernet, GPIO peripherals
- **Milestone**: Full Linux boot, interactive shell

**Total Timeline**: 16-24 weeks

## Future Enhancements
- **CURRENT PRIORITY**: OS Integration (see above) 🔥
- **Privilege Tests - Low Priority**:
  - `test_exception_all_ecalls.s` - Comprehensive ECALL test covering all 3 modes in one test
    - **Status**: Deferred (low priority)
    - **Reason**: Redundant - already have complete coverage via `test_umode_ecall`, `test_ecall_smode`, `test_exception_ecall_mmode`
    - **Value**: Nice-to-have for consolidation, but not necessary for functionality
    - **Effort**: 2-3 hours (macro complexity, privilege mode transitions)
- **Extensions**: Bit Manipulation (B), Vector (V), Crypto (K)
- **Performance**: Branch prediction, caching, out-of-order execution
- **System**: Debug module, PMP, Hypervisor extension
- **Verification**: Formal verification, FPGA synthesis, ASIC tape-out
