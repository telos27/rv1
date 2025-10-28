# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status
- **Achievement**: 🎉 **100% COMPLIANCE - 81/81 OFFICIAL TESTS PASSING** 🎉
- **Achievement**: 🎉 **PHASE 1.5 COMPLETE - 6/6 INTERRUPT TESTS PASSING** 🎉
- **Achievement**: 🎉 **FREERTOS BOOTS - SCHEDULER RUNNING** 🎉
- **Achievement**: ⚡ **BSS FAST-CLEAR - 2000x BOOT SPEEDUP** ⚡
- **Achievement**: 🎊 **FIRST UART OUTPUT - CONSOLE CHARACTERS WORKING!** 🎊
- **Achievement**: ✅ **TWO CRITICAL BUGS FIXED - FORWARDING & ADDRESS DECODE** ✅
- **Achievement**: 🔍 **RVC FP DECODER ENHANCED - C.FLDSP/C.FSDSP SUPPORT** 🔍
- **Achievement**: 🎯 **IMEM CORRUPTION BUG FIXED - UNIFIED MEMORY ARCHITECTURE** 🎯
- **Target**: RV32IMAFDC / RV64IMAFDC with full privilege architecture
- **Privilege Tests**: 33/34 passing (97%) - Phases 1-2-3-5-6-7 complete, Phase 4: 5/8 ✅
- **OS Integration**: Phase 2 IN PROGRESS 🚀 - IMEM bug fixed, FreeRTOS can now execute!
- **Recent Work**: IMEM Corruption Bug Fixed (2025-10-27 Session 30) - See below
- **Session 30 Summary**: Fixed critical unified memory bug - DMEM stores were corrupting IMEM due to missing address filtering
- **Next Step**: Continue FreeRTOS integration and debugging

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

**Session 30 (2025-10-27)**: IMEM Corruption Bug - FIXED! 🎯✅
- **Achievement**: Fixed critical unified memory bug blocking FreeRTOS execution!
- **Problem**: IMEM corrupted during runtime - stores to DMEM were also writing to IMEM
- **Root Cause #1**: DMEM loaded from same hex file as IMEM, causing BSS section overlap
- **Root Cause #2**: FENCE.I support connected ALL stores to IMEM without address filtering
- **Discovery**: IMEM overwrite detector showed corruption at cycles 292, 367, 441, 561 with data addresses
- **Fix #1**: Removed MEM_FILE from DMEM initialization in `rtl/rv_soc.v` (line 260)
- **Fix #2**: Added address filtering for IMEM writes: `(exmem_alu_result < IMEM_SIZE)` in `rtl/core/rv32i_core_pipelined.v` (line 674)
- **Verification**:
  - IMEM[0x210c] now reads correctly: 0x27068693 (ADDI a3,a3,624) ✓
  - FreeRTOS executes past address 0x210c without exceptions ✓
  - Quick regression: 14/14 passing ✓
- **Impact**: CRITICAL - affects all programs using DMEM, fixes Harvard architecture isolation
- **Status**: FIXED ✅, FreeRTOS can now boot!
- **Reference**: `docs/SESSION_30_IMEM_BUG_FIX.md`

**Session 29 (2025-10-27)**: IMEM Read Bug Investigation 🔍🔥
- **Achievement**: Root cause of mtval=NOP mystery identified - critical IMEM read bug!
- **Problem**: Instruction memory returns 0x00000000 instead of actual instruction data at runtime
- **Discovery Chain**:
  1. Exception at 0x210c with mtval=0x00000013 (NOP)
  2. Actual instruction at 0x210c is 0x27068693 (ADDI a3,a3,624 - legal!)
  3. Memory initialization shows correct data: mem[0x210c]=0x27068693 ✓
  4. Runtime fetch from 0x210c returns 0x00000000 ✗
- **Evidence**:
  - Fetch from 0x2108: Works correctly, returns 0x27068713 ✓
  - Fetch from 0x210c: Returns zeros 0x00000000 ✗
  - Fetch from 0x210e: Returns zeros 0x00000000 ✗
  - Fetch from 0x2110: Returns zeros 0x00000000 ✗
  - No memory writes detected to these addresses
- **Hypothesis**: Array indexing issue - 32-bit `halfword_addr` accessing 16-bit indexed array `mem[0:65535]`
- **Impact**: CRITICAL - Blocks FreeRTOS execution at address ≥0x210c
- **Status**: Root cause identified ✅, fix needed 🚧
- **Reference**: `docs/SESSION_29_IMEM_BUG_INVESTIGATION.md`

**Session 28 (2025-10-27)**: RVC FP Decoder Enhancement 🔍
- **Achievement**: Root cause identified - RVC decoder missing compressed FP instructions!
- **Problem**: FreeRTOS trap handler uses C.FSDSP/C.FLDSP to save/restore FPU context (32 FP registers)
- **Discovery**: Illegal instruction at 0x2548 = 0xa002 = C.FSDSP ft0, 0(sp), not implemented in RVC decoder
- **Root Cause**: RVC decoder marked funct3=101/op=10 as illegal (hit default case)
- **Fix**: Added full FP compressed instruction support to `rtl/core/rvc_decoder.v`:
  - C.FLDSP (funct3=001, op=10) - FLD from SP
  - C.FLWSP (funct3=011, op=10, RV32) - FLW from SP
  - C.FSDSP (funct3=101, op=10) - FSD to SP
  - C.FSWSP (funct3=111, op=10, RV32) - FSW to SP
- **Testing**: Quick regression 14/14 passing ✅, no regressions
- **Mystery**: Illegal instruction exceptions persist with mtval=0x00000013 (NOP) - investigated in Session 29
- **Status**: RVC decoder enhanced ✅, mtval=NOP traced to IMEM bug (Session 29)
- **Reference**: `docs/SESSION_28_RVC_FP_DECODER.md`

**Session 27 (2025-10-27)**: Critical Bug Fixes - Forwarding & Address Decode ✅✅
- **Achievement**: TWO critical correctness bugs identified and fixed!
- **Bug #1 - Forwarding**: WB→ID forwarding didn't check `memwb_valid`, causing stale data from flushed instructions to be forwarded
- **Fix #1**: Added `memwb_valid` gating to all 10 WB forwarding paths in forwarding unit
- **Bug #2 - Address Decode**: DMEM mask was 64KB (`0xFFFF_0000`) but FreeRTOS needs 1MB, causing stack/heap beyond 64KB to fail
- **Fix #2**: Changed DMEM_MASK to `0xFFF0_0000` (1MB range) in bus interconnect
- **Verification**: Memory operations now work correctly - write 0x22ac to 0x800c212c, read 0x22ac back (was 0x0!)
- **Impact**: CRITICAL - affects all programs using >64KB memory or relying on proper forwarding
- **Result**: FreeRTOS simulation runs full 500k cycles (was ~160), return addresses preserved correctly
- **Status**: Both bugs fixed ✅, quick regression 14/14 passing, but illegal instruction exceptions persist
- **Reference**: `docs/SESSION_27_CRITICAL_BUG_FIXES.md`

**Session 26 (2025-10-27)**: Return Address Corruption Debug 🔍
- **Achievement**: Root cause identified - ra register contains 0x0 instead of 0x22ac
- **Problem Chain**: JAL writes ra → SW saves ra to stack → LW loads 0x0 from stack → ret jumps to 0x0 → illegal instruction
- **Root Cause**: RAW hazard between JAL (writing x1 in WB) and SW (reading x1 in ID), forwarding path exists but may not be working
- **Evidence**: Link register trace shows JAL writes 0x22ac at cycle 121, but load from stack gets 0x0 at cycle 149
- **Instrumentation**: Added link register write monitoring, PC traces for cycles 117-155
- **Status**: Root cause identified ✅, fix implementation needed 🚧 (requires pipeline signal access)
- **Reference**: `docs/SESSION_26_RETURN_ADDRESS_DEBUG.md`

**Session 25 (2025-10-27)**: UART Debug & First Output! 🎊
- **Achievement**: First UART characters transmitted at cycle 145! (2 newlines successfully)
- **Root Cause**: Picolibc's `puts()` dereferenced fake FILE pointer `stdout = (FILE *)1`
- **Problem Chain**: `printf("const\n")` → GCC optimizes to `puts()` → dereference stdout+8 → jump to 0x0 → illegal instruction
- **Solution**: Custom `puts()` implementation in `syscalls.c` with direct UART calls
- **Instrumentation**: Added 91 lines of debug code to testbench (UART bus monitoring, function tracking, exception tracing)
- **Validation**: UART hardware path fully functional (Core → Bus → UART → TX)
- **Status**: First output ✅, remaining exceptions need debugging 🚧 (mepc=0x6 issue)
- **Reference**: `docs/SESSION_25_UART_DEBUG.md`

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
