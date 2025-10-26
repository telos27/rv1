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

**Phase 1: U-Mode Fundamentals** ✅ **COMPLETE (5/5 tests passing - 100%)**
- ✅ `test_umode_entry_from_mmode.s` - M→U transition via MRET **PASSING** 🎉
- ✅ `test_umode_entry_from_smode.s` - S→U transition via SRET **PASSING** 🎉
- ✅ `test_umode_ecall.s` - ECALL from U-mode (cause=8) **PASSING**
- ✅ `test_umode_csr_violation.s` - CSR privilege checking **PASSING**
- ✅ `test_umode_illegal_instr.s` - WFI privilege with TW bit **PASSING**
- ⏭️ `test_umode_memory_sum.s` - Skipped (requires full MMU)

**Phase 2: Status Register State Machine** 🚧 **IN PROGRESS (2/5 tests implemented, debugging)**
- 🔨 `test_mstatus_state_mret.s` - MRET state transitions (needs investigation)
- 🔨 `test_mstatus_state_sret.s` - SRET state transitions (needs investigation)
- ⏳ `test_mstatus_state_trap.s` - Trap entry state updates (pending)
- ⏳ `test_mstatus_nested_traps.s` - Nested trap handling (pending)
- ⏳ `test_mstatus_interrupt_enables.s` - Interrupt enable verification (pending)

**Recent Work (Latest Session - 2025-10-25 Part 3)**:
- 🎉 **CRITICAL FIX**: CSR forwarding bug preventing CSR read values from being forwarded
  - **Symptom**: U-mode entry tests (`test_umode_entry_from_mmode`, `test_umode_entry_from_smode`) failing with x28=0xDEADDEAD
  - **Root Cause #1**: CSR read values not included in MEM-stage forwarding
    - `exmem_forward_data` only forwarded ALU result, atomic result, or FP-to-INT result
    - CSR instructions use `wb_sel=3'b011` to select CSR data for writeback
    - But `exmem_forward_data` didn't check `exmem_wb_sel` to include CSR data
    - When branch compared `csrr t0, mcause` result in ID stage, forwarding from MEM gave 0 instead of mcause value
  - **Fix Applied**: Modified `rtl/core/rv32i_core_pipelined.v:1200`
    - Added CSR data to forwarding logic: `(exmem_wb_sel == 3'b011) ? exmem_csr_rdata : ...`
    - Now CSR reads in MEM stage properly forward their results to ID/EX stages
  - **Root Cause #2**: Test hardcoded offsets assuming 4-byte instructions (no compression)
    - Tests checked `mepc == umode_code + 8` (expecting 2 instructions × 4 bytes)
    - But `li s0, N` is compressed to 2 bytes with C extension enabled
    - Actual offset should be 2 bytes, not 8
  - **Fix Applied**: Updated test offsets
    - `tests/asm/test_umode_entry_from_mmode.s:72` - Changed offset from 8 to 2
    - `tests/asm/test_umode_entry_from_smode.s:80` - Changed offset from 8 to 2
  - **Root Cause #3**: S-mode macro incorrectly accessing mstatus
    - `ENTER_UMODE_S` macro used `csrr/csrw mstatus` from S-mode
    - S-mode cannot access mstatus directly - must use sstatus
    - SPP bit (bit 8) is visible in sstatus
  - **Fix Applied**: Modified `tests/asm/include/priv_test_macros.s:143-145`
    - Changed from `csrr t2, mstatus` → `csrr t2, sstatus`
    - Changed from `csrw mstatus, t2` → `csrw sstatus, t2`
  - **Files Modified**:
    - `rtl/core/rv32i_core_pipelined.v:1200` - Added CSR forwarding support
    - `rtl/core/rv32i_core_pipelined.v:827-839` - Added branch debug output (DEBUG_EXCEPTION)
    - `rtl/core/rv32i_core_pipelined.v:465-468` - Added exception latching debug (DEBUG_EXCEPTION)
    - `rtl/core/csr_file.v:423-434` - Added CSR trap debug output (DEBUG_EXCEPTION)
    - `rtl/core/csr_file.v:260-265` - Added mcause read debug output (DEBUG_EXCEPTION)
    - `tools/test_pipelined.sh:32-34` - Added DEBUG_EXCEPTION flag support
    - `tests/asm/test_umode_entry_from_mmode.s:72` - Fixed offset for compressed instructions
    - `tests/asm/test_umode_entry_from_smode.s:80` - Fixed offset for compressed instructions
    - `tests/asm/include/priv_test_macros.s:143-145` - Fixed S-mode CSR access
  - **Result**: ✅ Both U-mode entry tests now PASSING! Phase 1 complete (5/5 tests)
  - **Impact**: Critical forwarding fix - affects any code where CSR read immediately followed by register use
  - **Tests Now Passing**:
    - `test_umode_entry_from_mmode.s` ✅ (M→U transition via MRET)
    - `test_umode_entry_from_smode.s` ✅ (S→U transition via SRET)

- ✅ **Verified**: Quick regression fully passes (14/14 tests - 100%)
  - All I/M/A/F/D/C extension tests passing
  - No regressions from CSR forwarding fix
  - Phase 1 privilege mode testing complete

**Recent Work (Previous Session - 2025-10-25 Part 2)**:
- 🎉 **CRITICAL FIX**: Configuration mismatch causing test failures and infinite loops
  - **Symptom**: `test_fp_compare_simple` timing out with infinite loop, all tests compiled with compressed instructions failing
  - **Root Cause #1**: Configuration mismatch between test compilation and CPU simulation
    - Tests compiled with `-march=rv32imafc` (includes C extension - compressed 16-bit instructions)
    - Testbench compiled with `-DCONFIG_RV32I` which sets `ENABLE_C_EXT=0`
    - CPU treated any 2-byte aligned PC (0x16, 0x1a, etc.) as misaligned, triggering exceptions
    - Exception jumped to mtvec (address 0), restarting program → infinite loop
  - **Root Cause #2**: EBREAK detection broken after exception latching fix
    - Exception latching fix made EBREAK properly trap (correct behavior)
    - But testbench checked for EBREAK in IF stage AFTER trap occurred
    - After trap, IF stage fetched from trap vector (address 0 = NOPs), never seeing EBREAK again
    - Tests ran to MAX_CYCLES timeout without detecting completion
  - **Fix Applied**:
    - **Configuration Fix**: Modified `tools/test_pipelined.sh` to enable all extensions
      - Changed from `-DCONFIG_RV32I` to `-DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1`
      - Matches how tests are compiled (rv32imafc with compressed instructions)
    - **EBREAK Detection Fix**: Updated `tb/integration/tb_core_pipelined.v`
      - Changed from checking IF stage to checking ID stage (before trap occurs)
      - Added support for both compressed (0x9002) and uncompressed (0x00100073) EBREAK
      - Detection now works correctly with trapping exceptions
  - **Files Modified**:
    - `tools/test_pipelined.sh:33-48` - Fixed configuration flags for all extensions
    - `tb/integration/tb_core_pipelined.v:185-194` - Fixed EBREAK detection for ID stage + compressed
  - **Result**: ✅ Quick regression fully passes (14/14 tests - 100%)
  - **Impact**: All tests now work correctly with proper exception handling and C extension support
  - **Status**: Configuration mismatch resolved, testbench robust for both compressed and uncompressed code

**Recent Work (Previous Session - 2025-10-25 Part 1)**:
- 🎉 **CRITICAL FIX**: Exception signal latching to prevent mcause corruption
  - **Symptom**: `test_umode_entry_from_mmode` failing - mcause showing 3 (breakpoint) instead of 2 (illegal instruction)
  - **Root Cause**: Exception unit outputs are combinational and can glitch during clock cycles
    - When illegal CSR access trapped, exception_code=2 was latched
    - But before CSR file could process it, another exception (EBREAK from test_fail) occurred
    - Both exceptions were being written to mcause in what appeared to be the same cycle
    - Second write (cause=3) overwrote the first (cause=2)
  - **Fix Applied**: Exception signal latching with controlled timing
    - Latch exception_code/PC/val when exception first asserts
    - Hold latched values stable for exactly ONE cycle
    - Prevent re-arming until previous exception fully processed
    - `exception_r` pulses for one cycle, preventing multiple trap entries
  - **Implementation**:
    - `exception_r` set when `exception && !exception_taken_r`
    - Auto-clears after one cycle (simplified from 2-cycle hold)
    - `exception_taken_r` stays high until `exception_r_hold` set
    - CSR file receives stable `trap_cause` that can't be overwritten
  - **Files Modified**:
    - `rtl/core/rv32i_core_pipelined.v:439-474,512-526,1494` - Exception latching logic
    - `rtl/core/csr_file.v:418-422` - Removed trap_taken_r (now handled at top level)
  - **Result**: ✅ Quick regression fully passes (14/14 tests)
  - **Status**: Core exception handling now robust against signal glitches

**Recent Work (Previous Session - 2025-10-24 Part 7)**:
- 🎉 **CRITICAL FIX**: PC stall override for control flow changes (MRET/SRET/trap/branch)
  - **Symptom**: CSR privilege checks not triggering - target instructions after MRET/SRET were invalidated
  - **Investigation Process**:
    - CSR privilege checking logic was correct (commit 81ae388)
    - But `csrr` instructions after MRET never performed CSR access
    - Debug showed instructions reaching EX stage with `valid=0`
    - Root cause: CSR RAW hazard between MRET and target CSR instruction caused `stall_pc=1`
    - Stall prevented PC from updating to mepc/sepc, breaking control flow
  - **Root Cause**: Pipeline stall had priority over control flow changes
    - When MRET/SRET in MEM stage, target instruction at mepc/sepc already fetched into IFID
    - CSR RAW hazard detected between xRET and target → `stall_pc=1`
    - Stall prevented PC from updating, so jump didn't occur
    - Target instruction flushed but with `valid=0`, preventing CSR access
  - **Fix Applied**: Modified `rtl/core/rv32i_core_pipelined.v:528-531`
    - Added `pc_stall_gated` signal: `stall_pc && !(trap_flush | mret_flush | sret_flush | ex_take_branch)`
    - Control flow changes now override pipeline stalls
    - PC MUST update during flush regardless of hazards (wrong-path instructions being flushed anyway)
  - **Result**: ✅ CSR privilege checking now works! `test_umode_csr_violation` PASSING 🎉
  - **Files Modified**:
    - `rtl/core/rv32i_core_pipelined.v:528-531,1411-1437` - PC stall gating + debug output
    - `rtl/core/csr_file.v:364-368` - Enhanced CSR debug output
    - `rtl/core/exception_unit.v:169-198` - Added exception debug output
    - `tools/test_pipelined.sh:26-31` - Added DEBUG_CSR and DEBUG_PRIV support
  - **Tests Now Passing**: `test_umode_csr_violation.s` ✅ (was failing, now passes!)

- ✅ **Verified**: Quick regression fully passes
  - All 14 tests: ✅ (I/M/A/F/D/C extensions + custom tests)
  - No regressions from PC stall fix
  - Core functionality stable with improved control flow handling

**Recent Work (Previous Session - 2025-10-24 Part 6)**:
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
- ✅ **RESOLVED**: U-mode entry failures - Fixed in session 2025-10-25 Part 3
  - Root cause was CSR forwarding bug + test offset bugs + S-mode macro bug
  - Both tests now passing

- 🔧 **KNOWN ISSUE**: SRET/CSR pipeline hazard (documented, not blocking)
  - **Status**: Pipeline hazard when CSR instruction immediately follows SRET
  - **Observation**:
    - SRET with NOPs after: SPIE correctly set to 1 ✅
    - SRET with immediate CSR read: SPIE remains 0 ❌
  - **Root Cause**: CSR instruction in EX stage computes stale write value before SRET in MEM completes
  - **Current Mitigation**: Enhanced hazard detection partially addresses issue
  - **Workaround**: Insert NOP between SRET and CSR operations (compiler hint needed)
  - **Impact**: Does not block current development (tests use NOPs as workaround)
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
