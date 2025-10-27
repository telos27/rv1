# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status
- **Achievement**: 🎉 **100% COMPLIANCE - 81/81 OFFICIAL TESTS PASSING** 🎉
- **Target**: RV32IMAFDC / RV64IMAFDC with full privilege architecture
- **Privilege Tests**: 25/34 passing (74%) - Phases 1-2-5-6-7 complete ✅
- **Recent Work**: Phase 7 complete - Stress & regression tests ✅ (2025-10-26 Session 8) - See below

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
| 3: Interrupt CSRs | 🚧 Partial | 3/6 | mip/sip/mie/sie (3 skipped - need interrupt logic) |
| 4: Exception Coverage | 🚧 Partial | 2/8 | ECALL (4 blocked by hardware, 2 pending) |
| 5: CSR Edge Cases | ✅ Complete | 4/4 | Read-only CSRs, WARL fields, side effects, validity |
| 6: Delegation Edge Cases | ✅ Complete | 4/4 | Delegation to current mode, medeleg (writeback gating fixed) |
| 7: Stress & Regression | ✅ Complete | 2/2 | Rapid mode switching, comprehensive regression |

**Progress**: 25/34 tests passing (74%), 7 skipped/blocked, 2 pending

### Key Fixes (Recent Sessions)

**2025-10-26 (Session 9)**: Refactoring - Task 1.1 Complete - CSR Constants Header ✅
- **Achievement**: Eliminated CSR constant duplication, single source of truth
- **Created**: `rtl/config/rv_csr_defines.vh` (154 lines)
  - CSR addresses (25 constants): mstatus, misa, mie, mtvec, mepc, mcause, etc.
  - MSTATUS/SSTATUS bit positions (9 constants): MIE, SIE, MPIE, SPIE, MPP, SPP, SUM, MXR
  - CSR instruction opcodes (6 constants): CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
  - Exception cause codes (14 constants): illegal instruction, ECALL, page faults, etc.
  - Interrupt cause codes (6 constants): timer, software, external interrupts
  - Privilege mode encodings (3 constants): U=00, S=01, M=11
- **Modified**: 4 core files to use shared header
  - `rtl/core/csr_file.v` - removed 58 duplicate constants
  - `rtl/core/rv32i_core_pipelined.v` - removed 11 duplicate constants
  - `rtl/core/hazard_detection_unit.v` - removed 3 duplicate constants
  - `rtl/core/exception_unit.v` - removed 14 duplicate constants
- **Impact**:
  - 70 lines of duplicate definitions eliminated ✅
  - Single source of truth aligned with RISC-V spec ✅
  - Quick regression: 14/14 passing ✅
  - Zero regressions, purely organizational change ✅
- **Next**: Task 1.3 - Extract trap controller module
- **Reference**: `docs/REFACTORING_PLAN.md` - Phase 1 (1/2 tasks complete)

**2025-10-26 (Session 8)**: Phase 7 Complete - Stress & Regression Tests ✅
- **Achievement**: Implemented final 2 tests of privilege mode test suite (Phase 7)
- **Tests Created**:
  - `test_priv_rapid_switching.s`: Stress test with 20 M↔S privilege transitions (10 round-trips)
  - `test_priv_comprehensive.s`: All-in-one regression covering all major privilege features
- **Coverage**:
  - Rapid mode switching: Validates state preservation across many transitions
  - Comprehensive regression: Tests transitions, CSR access, delegation, state machine, exceptions
  - 6 stages: Basic M→S, M→S→U→S→M chains, CSR verification, state machine, exceptions, delegation
- **Results**:
  - Both tests PASSING ✅
  - Quick regression: 14/14 passing ✅
  - Compliance: 81/81 passing (100%) ✅
  - Phase 7 complete: 2/2 tests (100%)
- **Files**: `tests/asm/test_priv_rapid_switching.s`, `tests/asm/test_priv_comprehensive.s`

**2025-10-26 (Session 7)**: Writeback Gating & Test Infrastructure FIXED ✅
- **Problem**: Instructions after exceptions could write to registers before pipeline flush
  - Git operations deleted untracked hex files
  - No staleness detection - stale hex files caused mysterious test failures
  - Manual rebuild workflow error-prone
- **Root Cause**:
  - Register write enable not gated by `memwb_valid`
  - 1-cycle delay in `exception_taken_r` allowed next instruction to advance
  - Hex files were build artifacts (not tracked), got deleted on `git checkout`
  - No automatic rebuild when source files changed
- **Solution**: Multi-part fix for robustness
  - **Writeback Gating** (`rv32i_core_pipelined.v:853-867`): Gate register writes with `memwb_valid`
  - **Auto-Rebuild** (`tools/test_pipelined.sh:67-97`): Tests auto-rebuild missing/stale hex files
  - **Smart Rebuild** (`Makefile:350-399`): `make rebuild-hex` only rebuilds changed files
  - **Force Rebuild** (`Makefile:378-399`): `make rebuild-hex-force` rebuilds everything
- **Impact**:
  - `test_delegation_disable` now PASSING ✅ (Phase 6 complete: 4/4 tests)
  - No more "hex file not found" errors ✅
  - Tests work after git operations (checkout, pull, etc.) ✅
  - Quick regression: 14/14 passing ✅
  - Compliance: 79/79 passing (100%) ✅
- **Files**: `rtl/core/rv32i_core_pipelined.v`, `tools/test_pipelined.sh`, `Makefile`, `tools/README.md`

**2025-10-26 (Session 4)**: Exception Gating & Trap Target Computation FIXED ✅
- **Problem**: Exception propagation to subsequent instructions + trap delegation race condition
- **Symptoms**:
  - Exception signal fired for both faulting instruction AND next instruction
  - Duplicate ECALL exceptions with wrong privilege modes
  - `trap_target_priv` computed from stale `exception_code_r` causing wrong delegation
- **Solution**: Multi-part fix for exception handling
  - **Exception Gating** (`rv32i_core_pipelined.v:452`): Added `exception_gated` to prevent propagation
  - **Trap Target Computation** (`rv32i_core_pipelined.v:454-489`): Core-side `compute_trap_target()` function using un-latched signals
  - **CSR Delegation Export** (`csr_file.v:51, 621`): Added `medeleg_out` port for direct access
- **Impact**:
  - Exception propagation bug FIXED ✅
  - Trap delegation timing FIXED ✅
  - Quick regression: 14/14 passing ✅
  - Compliance: 81/81 still passing ✅
- **Files**: `rtl/core/rv32i_core_pipelined.v`, `rtl/core/csr_file.v`
- **Remaining Issue**: `test_delegation_disable` - ECALL not detected initially

**2025-10-26 (Session 6)**: Trap Latency Architectural Analysis ⚙️
- **Investigation**: Deep dive into `test_delegation_disable` failure - register corruption after ECALL
- **Root Cause Identified**: Synchronous pipeline limitation creates inherent 1-cycle trap latency
  - Exception detected in cycle N
  - Pipeline flush synchronous → takes effect in cycle N+1
  - Next instruction advances to IDEX before flush completes
  - Result: Instruction after exception may execute before trap
- **Attempted Fixes**:
  - ✅ 0-cycle trap latency: Changed `trap_flush` to use `exception_gated` (immediate)
  - ✅ Updated CSR trap inputs to use current exception signals (non-registered)
  - ❌ Combinational valid gating: Creates oscillation loop, all tests timeout
- **Impact**:
  - Quick regression: 14/14 passing ✅
  - Compliance: 81/81 passing ✅
  - `test_delegation_disable`: Still fails (architectural limitation)
- **Conclusion**: Documented as architectural characteristic in KNOWN_ISSUES.md
  - Proposed 4 solution approaches (writeback gating to full speculative execution)
  - Recommended: Accept 1-cycle latency, ensure no harmful side effects
  - No impact on real-world code or official compliance tests
- **Files**: `rtl/core/rv32i_core_pipelined.v:565,567,1567-1570`, `docs/KNOWN_ISSUES.md`

**2025-10-26 (Session 5)**: CSR Write Exception Gating FIXED ✅
- **Problem**: CSR writes committing even when instruction causes illegal instruction exception
- **Root Cause**: `csr_we` signal not gated by exception detection
  - When CSR instruction caused illegal exception, CSR write still executed
  - Example: `csrw medeleg, zero` from S-mode → illegal exception, but write committed
- **Solution**: Added exception gating to CSR write enable (`rv32i_core_pipelined.v:1564`)
  - Changed: `.csr_we(idex_csr_we && idex_valid)`
  - To: `.csr_we(idex_csr_we && idex_valid && !exception)`
- **Impact**:
  - ECALL detection now working ✅ (cause=9 correctly generated)
  - CSR corruption on illegal access FIXED ✅
  - Quick regression: 14/14 passing ✅
  - Compliance: 81/81 still passing ✅
- **Files**: `rtl/core/rv32i_core_pipelined.v:1564`
- **Remaining Issue**: `test_delegation_disable` - Architectural trap latency (Session 6 analysis)

**2025-10-26 (Session 3)**: Phase 6 - Delegation logic FIXED ✅
- **Problem**: Trap delegation used forwarded privilege mode from xRET instructions
- **Solution**: Separated `actual_priv` (for delegation) from `effective_priv` (for CSR checks)
  - Changed `.actual_priv` connection from `effective_priv` to `current_priv`
  - Ensures delegation decisions based on actual privilege of trapping instruction
  - Fixed test_delegation_disable test bug (S-mode can't write medeleg)
- **Impact**:
  - `test_delegation_to_current_mode` ✅
  - `test_medeleg` ✅
  - `test_phase10_2_delegation` ✅
  - Phase 6: 3/4 tests passing (75%)
- **Files**: `rtl/core/rv32i_core_pipelined.v:1543`, `tests/asm/test_delegation_disable.s`
- **Known Issue**: `test_delegation_disable` has trap timing issue (documented in KNOWN_ISSUES.md)

**2025-10-26 (Session 2)**: Privilege mode forwarding bug FIXED ✅
- **Problem**: CSR access immediately after MRET/SRET used stale privilege mode
- **Solution**: Implemented privilege mode forwarding (similar to data forwarding)
  - Forward new privilege from MRET/SRET in MEM stage to EX stage
  - Separate `effective_priv` (for CSR checks) from latched privilege (for trap delegation)
  - Added `exception_target_priv_r` register to break combinational feedback loop
  - Changed trap flush to use registered exception (1-cycle delay)
- **Impact**: `test_delegation_to_current_mode` now PASSING ✅
- **Trade-off**: Introduced 1-cycle trap latency (some tests need investigation)
- **Files**: `rtl/core/rv32i_core_pipelined.v`, `rtl/core/csr_file.v`

**2025-10-26 (Session 1)**: Phase 5 completed - CSR edge cases (4/4 tests passing)
- `test_csr_readonly_verify.s` - Read-only CSRs return consistent values (mvendorid, marchid, mimpid, mhartid, misa)
- `test_csr_warl_fields.s` - WARL constraints verified (MPP, SPP, mtvec mode)
- `test_csr_side_effects.s` - CSR side effects (mstatus↔sstatus, mie↔sie, mip↔sip)
- `test_csr_illegal_access.s` - Valid CSRs accessible, proper decoding verified
- Quick regression: 14/14 passing ✅

**2025-10-26**: Phase 4 started - Exception coverage
- Hardware constraints documented (misaligned access supported, EBREAK blocked)

**2025-10-25**: Phases 2-3 completed
- CSR forwarding bug fixed (MEM stage forwarding)
- MRET/SRET forwarding timing issue resolved (hold-until-consumed)
- Configuration mismatch fixed (C extension enabled)
- Exception signal latching to prevent mcause corruption

**2025-10-24**: Phase 1 completed + core fixes
- Precise exception handling (instructions before exception complete)
- MRET/SRET executing multiple times fixed
- sstatus_mask bug fixed (SPIE/SPP visibility)
- PC stall override for control flow changes
- MMU bare mode handshake logic fixed

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

## Future Enhancements
- **NEXT PRIORITIES**:
  - Phase 3: Interrupt handling tests (requires interrupt injection capability)
  - Phase 4: Exception coverage (EBREAK, misaligned access, page faults)
  - Remaining privilege mode tests (9 tests in Phases 3-4)
- **Extensions**: Bit Manipulation (B), Vector (V), Crypto (K)
- **Performance**: Branch prediction, caching, out-of-order execution
- **System**: Debug module, PMP, Hypervisor extension
- **Verification**: Formal verification, FPGA synthesis, ASIC tape-out
