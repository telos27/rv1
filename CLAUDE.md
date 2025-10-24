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

**Phase 1: U-Mode Fundamentals** ✅ **COMPLETE (5/5 tests passing)**
- ✅ `test_umode_entry_from_mmode.s` - M→U transition via MRET
- ✅ `test_umode_entry_from_smode.s` - S→U transition via SRET
- ✅ `test_umode_ecall.s` - ECALL from U-mode (cause=8)
- ✅ `test_umode_csr_violation.s` - CSR privilege checking
- ✅ `test_umode_illegal_instr.s` - WFI privilege with TW bit
- ⏭️ `test_umode_memory_sum.s` - Skipped (requires full MMU)

**Known Issues Discovered**:
- 🐛 SRET/MRET don't trap in U-mode (RTL privilege checking bug)

**Remaining Phases** (7 Phases, 29 tests remaining):
- Phase 2: Status Register State Machine (5 tests) - 🟠 HIGH - **NEXT**
- Phase 3: Interrupt Handling (6 tests) - 🟠 HIGH
- Phase 4: Exception Coverage (8 tests) - 🟡 MEDIUM
- Phase 5: CSR Edge Cases (4 tests) - 🟡 MEDIUM
- Phase 6: Delegation Edge Cases (3 tests) - 🟢 LOW
- Phase 7: Stress & Regression (2 tests) - 🟢 LOW

**Progress**:
- Tests Implemented: 5/34 (15%)
- Tests Passing: 5/5 (100%)
- Coverage: U-mode fundamentals, CSR privilege, basic exceptions

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
