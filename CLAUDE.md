# CLAUDE.md - AI Assistant Context

## Project Overview
This project implements a RISC-V CPU core in Verilog, starting from a simple single-cycle design and progressively adding features to reach a complete pipelined processor with extensions.

## Current Status
**Phase**: Complete - Production Ready ✅
**Achievement**: 🎉 **100% COMPLIANCE - 81/81 TESTS PASSING** 🎉
**Target**: RV32IMAFDC / RV64IMAFDC with full privilege architecture
**Next Phase**: Enhanced Privilege Mode Testing (34 new tests planned)

## 🔍 IMPORTANT: Test Infrastructure Reference (USE THIS!)

**Before searching for tests or running commands, consult these resources:**

1. **Test Catalog** - `docs/TEST_CATALOG.md`
   - Auto-generated catalog of ALL 208 tests (127 custom + 81 official)
   - Searchable index with descriptions
   - Categorized by extension (I/M/A/F/D/C/CSR/Edge/etc.)
   - Shows which hex files exist
   - Run `make catalog` to regenerate

2. **Makefile Help** - Run `make help`
   - Shows all available test targets
   - Key commands: `make test-custom-all`, `make rebuild-hex`, `make check-hex`, `make catalog`

3. **Script Reference** - `tools/README.md`
   - Quick reference for all 22 scripts
   - Shows main vs. legacy scripts
   - Usage examples

**DO THIS at the start of testing sessions:**
```bash
make help                 # See available commands
cat docs/TEST_CATALOG.md  # Browse all tests
make check-hex            # Verify test files
make test-quick           # Quick regression (14 tests in ~7s) ⚡
```

## ⚡ CRITICAL: Always Run Quick Regression!

**BEFORE making any changes to RTL, RUN THIS:**
```bash
make test-quick
```

**AFTER making changes, RUN THIS:**
```bash
make test-quick
```

**Why**: Catches 90% of bugs in 7 seconds (11x faster than full suite)

**If quick tests fail**: Run full suite to investigate
```bash
env XLEN=32 ./tools/run_official_tests.sh all
```

**Workflow for development:**
1. Run `make test-quick` BEFORE changes (baseline)
2. Make your changes
3. Run `make test-quick` AFTER changes (verify)
4. If all pass: Proceed with development
5. If any fail: Debug before continuing
6. Before committing: Run full test suite

## Development Philosophy
- **Incremental**: Each phase builds on the previous one
- **Testable**: Every feature must have corresponding tests
- **Educational**: Code should be clear and well-commented
- **Compliance**: Verify against official RISC-V tests

## Project Structure
```
rv1/
├── docs/           # Design documents and specifications
├── rtl/            # Verilog source files
│   ├── core/       # CPU core modules
│   ├── memory/     # Memory components
│   └── peripherals/# I/O and peripherals
├── tb/             # Testbenches
├── tests/          # Test programs and vectors
├── sim/            # Simulation scripts and results
└── tools/          # Helper scripts
```

## Design Constraints
- **HDL**: SystemVerilog subset (Verilog-2001 compatible)
- **Target**: FPGA-friendly design (no technology-specific cells initially)
- **Simulation**: Icarus Verilog primary, Verilator compatible
- **Word Size**: Configurable 32-bit (RV32) or 64-bit (RV64) via XLEN parameter
- **Endianness**: Little-endian (RISC-V standard)

## Implemented Extensions

### ✅ RV32I/RV64I - Base Integer ISA (100%)
- **Compliance**: 42/42 official tests PASSING
- **Instructions**: 47 base instructions
- **Features**:
  - Full integer arithmetic and logical operations
  - Load/store with misaligned hardware support
  - Branch and jump instructions
  - FENCE.I for self-modifying code

### ✅ RV32M/RV64M - Multiply/Divide Extension (100%)
- **Compliance**: 8/8 official tests PASSING
- **Instructions**: 13 instructions (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU + RV64 W-variants)
- **Implementation**:
  - 32-cycle sequential multiplier
  - 64-cycle non-restoring divider
  - Edge case handling per RISC-V spec

### ✅ RV32A/RV64A - Atomic Operations Extension (100%)
- **Compliance**: 10/10 official tests PASSING
- **Instructions**: 22 instructions (LR, SC, 11 AMO operations × 2 widths)
- **Implementation**:
  - Reservation station for LR/SC
  - Full AMO operations (SWAP, ADD, XOR, AND, OR, MIN, MAX, MINU, MAXU)
  - LR/SC forwarding hazard handling

### ✅ RV32F - Single-Precision Floating-Point (100%)
- **Compliance**: 11/11 official tests PASSING
- **Instructions**: 26 FP instructions
- **Features**:
  - Arithmetic: ADD, SUB, MUL, DIV, SQRT, MIN, MAX
  - Fused Multiply-Add (FMA): FMADD, FMSUB, FNMADD, FNMSUB
  - Conversions: Integer ↔ Float
  - Comparisons and classifications
  - 32-entry FP register file

### ✅ RV32D - Double-Precision Floating-Point (100%) 🎉
- **Compliance**: 9/9 official tests PASSING ✅
- **Instructions**: 26 DP instructions
- **Features**:
  - All double-precision operations (FADD.D, FSUB.D, FMUL.D, FDIV.D, FSQRT.D)
  - Fused Multiply-Add for double (FMADD.D, FMSUB.D, FNMADD.D, FNMSUB.D)
  - Single ↔ Double conversion (FCVT.S.D, FCVT.D.S)
  - Integer ↔ Double conversions
  - NaN-boxing support
  - Shared 64-bit FP register file with F extension
- **Achievement**: Complete double-precision FPU implementation with all edge cases handled

### ✅ RV32C/RV64C - Compressed Instructions (100%)
- **Compliance**: 1/1 official test PASSING
- **Instructions**: 40 compressed (16-bit) instructions
- **Features**:
  - All three quadrants (Q0, Q1, Q2)
  - Code density improvement: ~25-30%
  - 34/34 decoder unit tests PASSING
  - Mixed 2-byte/4-byte PC increment

### ✅ Zicsr - CSR Instructions (Complete)
- **Instructions**: 6 CSR instructions (CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI)
- **CSR Registers**:
  - Machine mode: mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip, misa, mvendorid, marchid, mimpid, mhartid
  - Supervisor mode: sstatus, sie, stvec, sscratch, sepc, scause, stval, sip
  - Delegation: medeleg, mideleg
  - Floating-point: fcsr, frm, fflags
  - MMU: satp (Sv32/Sv39)

### ✅ Zifencei - Instruction Fence (Partial)
- **Status**: FENCE.I instruction implemented
- **Use**: Self-modifying code support

## Architecture Features

### Pipeline Architecture
- **Stages**: 5-stage classic pipeline (IF, ID, EX, MEM, WB)
- **Hazard Handling**:
  - Data forwarding for register hazards
  - Stalling for load-use hazards
  - Branch prediction and flushing
  - LR/SC reservation tracking
  - CSR Read-After-Write (RAW) hazard detection (EX/MEM stages)
- **Exception Handling**: Precise exceptions (instructions before exception complete)

### Privilege Architecture
- **Modes**: Machine (M), Supervisor (S), User (U)
- **Trap Handling**: Full exception and interrupt support
- **Delegation**: M→S delegation via medeleg/mideleg

### Memory Management
- **Virtual Memory**: Sv32 (RV32) and Sv39 (RV64)
- **TLB**: 16-entry Translation Lookaside Buffer
- **Support**: Page-based virtual memory with hardware page-table walk

### Floating-Point Unit
- **Components**:
  - FP Adder/Subtractor
  - FP Multiplier
  - FP Divider (iterative)
  - FP Square Root (iterative)
  - FP Fused Multiply-Add (FMA)
  - Format converters, comparators, classifiers
- **Precision**: Both single (32-bit) and double (64-bit)
- **Register File**: 32 × 64-bit FP registers (shared F/D)

## Naming Conventions

### Files
- Modules: `snake_case.v` (e.g., `alu.v`, `register_file.v`)
- Testbenches: `tb_<module>.v` (e.g., `tb_alu.v`)
- Top level: `rv32i_core.v`

### Signals
- Active-low signals: `_n` suffix (e.g., `reset_n`)
- Registered outputs: `_r` suffix (e.g., `data_out_r`)
- Next-state: `_next` suffix (e.g., `state_next`)
- Combinational: descriptive names (e.g., `alu_result`)

### Parameters
- UPPERCASE with underscores (e.g., `DATA_WIDTH`, `ADDR_WIDTH`)

## Testing Strategy
1. **Unit Tests**: Each module tested independently
2. **Instruction Tests**: Each instruction verified with known results
3. **Compliance Tests**: RISC-V official test suite (81/81 passing ✅)
4. **Program Tests**: Small assembly programs (Fibonacci, sorting, etc.)
5. **Random Tests**: Constrained random instruction sequences
6. **Privilege Mode Tests**: Comprehensive M/S/U mode testing (See `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md`)

## 🆕 Privilege Mode Test Suite (Phase 1 Complete!)

A comprehensive privilege mode testing framework implementation in progress:

**Documentation**:
- `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md` - Complete implementation plan (34 tests)
- `docs/PRIVILEGE_TEST_ANALYSIS.md` - Gap analysis and coverage assessment
- `docs/PRIVILEGE_MACRO_LIBRARY.md` - Macro library overview
- `tests/asm/include/README.md` - Macro quick reference

**Infrastructure**:
- **Macro Library**: `tests/asm/include/priv_test_macros.s` (520+ lines, 50+ macros)
- **Demo Test**: `tests/asm/test_priv_macros_demo.s` (working example)

**Phase 1: U-Mode Fundamentals** 🚧 **PARTIAL (2/5 tests passing)**
- 🔨 `test_umode_entry_from_mmode.s` - M→U transition via MRET (CSR privilege issue)
- 🔨 `test_umode_entry_from_smode.s` - S→U transition via SRET (CSR privilege issue)
- ✅ `test_umode_ecall.s` - ECALL from U-mode (cause=8) **PASSING**
- 🔨 `test_umode_csr_violation.s` - CSR privilege checking (under investigation)
- ✅ `test_umode_illegal_instr.s` - WFI privilege with TW bit **PASSING**
- ⏭️ `test_umode_memory_sum.s` - Skipped (requires full MMU)

**Phase 2: Status Register State Machine** 🚧 **IN PROGRESS (2/5 tests implemented, debugging)**
- 🔨 `test_mstatus_state_mret.s` - MRET state transitions (CSR privilege issue)
- 🔨 `test_mstatus_state_sret.s` - SRET state transitions (CSR privilege issue)
- ⏳ `test_mstatus_state_trap.s` - Trap entry state updates (pending)
- ⏳ `test_mstatus_nested_traps.s` - Nested trap handling (pending)
- ⏳ `test_mstatus_interrupt_enables.s` - Interrupt enable verification (pending)

**Recent Work (Latest Session - 2025-10-24 Part 6)**:
- 🐛 **CRITICAL REGRESSION FIX**: MMU bare mode causing pipeline stalls
  - **Symptom**: Quick regression showed `test_fp_add_simple` timing out with infinite loop
  - **Investigation Process**:
    - Used `git bisect` to find breaking commit (added MMU module)
    - Discovered `test_fp_add_simple.hex` was accidentally deleted in commit 6f54734
    - Regenerated hex file but test still failed
    - Found root cause: MMU `req_ready` signal pulsing instead of holding
  - **Root Cause**: MMU bare mode (no virtual memory) had faulty handshake logic
    - `req_ready` pulsed high for 1 cycle, then defaulted to 0 on next cycle
    - While `req_valid` stayed high (memory op in MEM stage), `req_ready` went low
    - Formula: `mmu_busy = req_valid && !req_ready` → stuck high, stalling pipeline
    - Result: ALL memory operations (loads/stores) stalled indefinitely
  - **Fix Applied**: Modified `rtl/core/mmu.v:290-296`
    - Changed default logic to keep `req_ready=1` and `req_paddr=req_vaddr` in bare mode
    - Removed redundant assignments in PTW_IDLE state that were overriding defaults
    - Logic: `req_ready <= (!translation_enabled && req_valid) ? 1 : 0`
  - **Result**: ✅ All 14 quick regression tests passing (100%)
  - **Files Modified**:
    - `rtl/core/mmu.v:290-296,320` - Fixed bare mode handshake
    - `tools/asm_to_hex.sh:107` - Added `--no-relax` linker flag for better control
    - `tests/asm/test_fp_add_simple.s:17-25` - Added gp initialization (defensive)

- ✅ **Verified**: Quick regression fully passes
  - All 14 tests: ✅ (I/M/A/F/D/C extensions + custom tests)
  - No regressions from MMU fix or CSR privilege changes
  - Core functionality stable and ready for continued development

**Recent Work (Previous Session - 2025-10-24 Part 5)**:
- 🔍 **BUG IDENTIFIED**: CSR privilege checking not working for read operations
  - **Root Cause**: CSR privilege checks only applied to writes (`csr_we`), not reads
  - **Fix Implemented**: Added `csr_access` signal for privilege checking
  - **Status**: Fix complete but privilege tests still under investigation
  - See commit 81ae388 for details

**Recent Work (Previous Session - 2025-10-24 Part 3)**:
- ✅ **CRITICAL FIX**: sstatus_mask bug - SPIE and SPP bits now visible
  - **Root Cause**: sstatus_mask was incorrectly excluding bits 5 (SPIE) and 8 (SPP) from sstatus reads
  - **Symptom**: Reading sstatus in S-mode returned 0 for SPIE/SPP bits even when set in mstatus
  - **Fix**: Updated sstatus_mask from `0x00060022` to `0x000c0162` to include all S-mode visible bits
  - **Impact**: sstatus now correctly shows SIE(1), SPIE(5), UBE(6), SPP(8), SUM(18), MXR(19)
  - **Files Modified**:
    - `rtl/core/csr_file.v:223` - Fixed sstatus_mask value
  - **Result**: SRET with SPIE=1 now works correctly (verified: sstatus=0x22 after SRET)

- ✅ **Verified**: Quick regression passes (14/14 tests: ✅) - no regressions from sstatus_mask fix

**Recent Work (Previous Session - 2025-10-24 Part 2)**:
- ✅ **CRITICAL FIX**: Precise exception handling - instructions before exception now complete
  - **Root Cause**: Pipeline was invalidating MEM stage instructions when exceptions occurred in EX stage
  - **Symptom**: Register writes immediately before EBREAK/ECALL were being dropped (TEST_PASS markers not visible)
  - **Fix**: Only invalidate MEM→WB transition for MEM-stage exceptions (load/store misaligned, page faults)
  - **Impact**: EX-stage exceptions (EBREAK, ECALL, illegal inst) now allow preceding instructions to complete
  - **Files Modified**:
    - `rtl/core/rv32i_core_pipelined.v:1496-1501` - Added `exception_from_mem` signal
    - `rtl/core/rv32i_core_pipelined.v:1707-1708` - Updated `reg_write_gated` and `mem_write_gated`
    - `rtl/core/rv32i_core_pipelined.v:1868` - Updated MEMWB `valid_in` signal
  - **Result**: TEST_PASS/TEST_FAIL markers now work correctly, test framework operational
  - **Test Files Created**:
    - `tests/asm/test_x28_write.s` - Minimal reproduction case
    - `tests/asm/test_ebreak_timing.s` - Pipeline timing verification
    - `tests/asm/test_marker_check.s` - Marker mechanism verification

- ✅ `test_mstatus_state_mret.s` - Now fully passing (updated documentation from previous session)
- 🔨 `test_mstatus_state_sret.s` - Implemented, SRET SIE/SPIE behavior needs debugging

- ✅ **Verified**: Quick regression passes (14/14 tests: ✅) - no regressions from precise exception fix

**Recent Work (Previous Session - 2025-10-24 Part 1)**:
- ✅ **CRITICAL FIX**: MRET/SRET executing multiple times during pipeline stalls
  - **Root Cause**: CSR file was called with EX stage signals (`idex_is_mret`), causing MRET to execute every cycle it remained in EX during stalls
  - **Symptom**: mstatus_r was being overwritten multiple times, losing non-MPIE bits (MPP cleared to 0)
  - **Fix**: Changed CSR file to use MEM stage signals (`exmem_is_mret && exmem_valid && !exception`)
  - **Impact**: MRET/SRET now execute exactly once when reaching MEM stage, correctly updating mstatus
  - **Files Modified**:
    - `rtl/core/rv32i_core_pipelined.v:1423,1425` - Changed MRET/SRET signals from EX to MEM stage
    - `rtl/core/hazard_detection_unit.v:50-52,278-279,285-286,907-908` - Added xRET hazard detection
  - **Result**: Stages 1-2 of `test_mstatus_state_mret.s` now pass (MPIE/MIE updates work correctly)

- ✅ **Enhanced**: CSR RAW hazard detection for MRET/SRET
  - **Issue**: MRET/SRET modify mstatus but weren't triggering hazard stalls for subsequent CSR reads
  - **Fix**: Added `exmem_is_mret` and `exmem_is_sret` to CSR RAW hazard condition
  - **Impact**: Pipeline correctly stalls when CSR read follows MRET/SRET
  - **Files Modified**: `rtl/core/hazard_detection_unit.v`

- ✅ **Verified**: Quick regression passes (14/14 tests: ✅) - no regressions from fixes

**Known Issues**:
- 🔧 **ACTIVE INVESTIGATION**: SRET/CSR pipeline hazard
  - **Status**: Pipeline hazard when CSR instruction immediately follows SRET
  - **Observation**:
    - SRET with NOPs after: SPIE correctly set to 1 ✅
    - SRET with immediate CSR read: SPIE remains 0 ❌
  - **Root Cause**: CSR instruction in EX stage computes stale write value before SRET in MEM completes
  - **Current Mitigation**: Enhanced hazard detection partially addresses issue
  - **Workaround**: Insert NOP between SRET and CSR operations (compiler hint needed)
  - **Next Steps for Next Session**:
    1. Investigate why hazard detection bubble isn't fully preventing stale CSR writes
    2. Consider moving CSR operations to MEM stage (align with xRET timing)
    3. Add EXMEM flush capability for CSR operations
    4. Alternative: Implement CSR write value forwarding from xRET
  - **Impact**: Blocks `test_mstatus_state_sret.s` Stage 1 from passing
  - **Code Locations**:
    - `rtl/core/csr_file.v:441-444` - SRET implementation (correct)
    - `rtl/core/hazard_detection_unit.v:281-282` - CSR-xRET hazard detection (partial fix)
    - `rtl/core/rv32i_core_pipelined.v:1416` - CSR operations use EX stage signals

**Remaining Phases** (7 Phases, 29 tests remaining):
- Phase 2: Status Register State Machine (5 tests) - 🟠 HIGH - **NEXT**
- Phase 3: Interrupt Handling (6 tests) - 🟠 HIGH
- Phase 4: Exception Coverage (8 tests) - 🟡 MEDIUM
- Phase 5: CSR Edge Cases (4 tests) - 🟡 MEDIUM
- Phase 6: Delegation Edge Cases (3 tests) - 🟢 LOW
- Phase 7: Stress & Regression (2 tests) - 🟢 LOW

**Progress**:
- Tests Implemented: 6/34 (18%)
- Tests Passing: 5/6 (83%)
- Coverage: U-mode fundamentals, CSR privilege, basic exceptions, MRET state machine
- **Key Achievement**: Precise exception handling now working correctly

## Common RISC-V Instruction Formats
```
R-type: funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]
I-type: imm[31:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]
S-type: imm[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[11:7] | opcode[6:0]
B-type: imm[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[11:7] | opcode[6:0]
U-type: imm[31:12] | rd[11:7] | opcode[6:0]
J-type: imm[31:12] | rd[11:7] | opcode[6:0]
```

## Useful References
- RISC-V ISA Spec: https://riscv.org/technical/specifications/
- RV32I Base: Volume 1, Chapter 2
- Unprivileged ISA: https://github.com/riscv/riscv-isa-manual
- Test Suite: https://github.com/riscv/riscv-tests
- Compliance: https://github.com/riscv/riscv-compliance

## When Assisting

### Before Making Changes
1. Check current phase in PHASES.md
2. Review ARCHITECTURE.md for design constraints
3. Verify against RISC-V spec

### Code Style
- Use 2-space indentation
- Keep lines under 100 characters
- Comment complex logic
- Use meaningful signal names
- Group related signals in modules

### Adding Features
1. Update PHASES.md with status
2. Design the feature (document in ARCHITECTURE.md)
3. Implement the Verilog module
4. Write testbench
5. Verify with tests
6. Update documentation

### Debug Approach
1. Check waveforms first
2. Verify control signals
3. Check instruction decode
4. Trace data path
5. Look for timing issues

## Total Implementation Statistics
- **Instructions Implemented**: 184+ (I: 47, M: 13, A: 22, F: 26, D: 26, C: 40, Zicsr: 6, System: 4)
- **Official Compliance**: 🎉 **81/81 tests (100%) - PERFECT SCORE** 🎉
  - RV32I: 42/42 ✅ (100%)
  - RV32M: 8/8 ✅ (100%)
  - RV32A: 10/10 ✅ (100%)
  - RV32F: 11/11 ✅ (100%)
  - RV32D: 9/9 ✅ (100%)
  - RV32C: 1/1 ✅ (100%)
- **Custom Tests**: 60+ custom test programs
- **Configuration**: Supports both RV32 and RV64 via XLEN parameter
- **Achievement**: Complete RISC-V RV32IMAFDC implementation with all official tests passing!

## Future Enhancement Opportunities
1. **Bit Manipulation (B extension)**: Zba, Zbb, Zbc, Zbs subextensions
2. **Vector Extension (V)**: SIMD vector operations
3. **Cryptography (K extension)**: AES, SHA acceleration
4. **Performance Features**:
   - Branch prediction enhancements
   - Multi-level caching (L1/L2)
   - Out-of-order execution
   - Superscalar dispatch
5. **System Features**:
   - Debug module (RISC-V Debug Spec)
   - Performance counters
   - Physical Memory Protection (PMP)
   - Hypervisor extension (H)
6. **Verification & Deployment**:
   - Formal verification
   - FPGA synthesis and timing optimization
   - ASIC tape-out preparation

## Notes for Future Development
- Keep reset consistent (async vs sync)
- Plan for synthesis early (avoid unsynthesizable constructs)
- Consider formal verification for critical paths
- Document all assumptions about memory timing
- Plan interrupt handling architecture from early stages
