# Next Session Quick Start Guide

**Date Created**: 2025-10-10
**Current Status**: Phase 5 Parameterization COMPLETE ✅
**Next Phase**: Testing, Validation, and Future Extensions

---

## What Was Just Completed

**Phase 5 - Parameterization (100% Complete)**
- ✅ All 16 modules parameterized for RV32/RV64 support
- ✅ Build system with 5 configuration targets
- ✅ RV64 instruction support (LD, SD, LWU)
- ✅ Comprehensive documentation created
- ✅ Both RV32I and RV64I compile successfully

See `SESSION_SUMMARY_2025-10-10_phase5_complete.md` for full details.

---

## Current State of the Project

### What's Working
- ✅ **RV32I**: 40/42 compliance tests passing (95%)
- ✅ **Build System**: 5 configurations ready (rv32i, rv32im, rv32imc, rv64i, rv64gc)
- ✅ **CSR Support**: 13 Machine-mode CSRs implemented
- ✅ **Exception Handling**: 6 exception types with trap support
- ✅ **Pipeline**: 5-stage with 3-level forwarding and hazard detection
- ✅ **Parameterization**: All modules support XLEN=32 or XLEN=64

### What Needs Testing
- ⏳ **RV32I Regression**: Verify 40/42 compliance tests still pass after parameterization
- ⏳ **RV64I Functionality**: Test RV64-specific instructions (LD, SD, LWU)
- ⏳ **RV64I Compliance**: Run RV64I compliance suite

### What's Not Implemented Yet
- ❌ **M Extension**: Multiply/divide instructions
- ❌ **A Extension**: Atomic instructions
- ❌ **C Extension**: Compressed instructions
- ❌ **Cache**: I-cache and D-cache
- ❌ **RV64M**: 64-bit multiply/divide

---

## Quick Start Commands

### Build and Run RV32I
```bash
cd /home/lei/rv1

# Build RV32I pipelined core
make pipelined-rv32i

# Run simulation
make run-rv32i

# Run compliance tests
make compliance
```

### Build and Run RV64I
```bash
# Build RV64I pipelined core
make pipelined-rv64i

# Run simulation
make run-rv64i

# Note: RV64I compliance tests not yet set up
```

### Run Unit Tests
```bash
make test-unit       # All unit tests
make test-alu        # Just ALU
make test-regfile    # Just register file
make test-decoder    # Just decoder
```

### Build System
```bash
make help            # Show all available targets
make info            # Show configuration details
make clean           # Clean build artifacts
```

---

## Recommended Next Steps

### Option 1: Verification & Testing (Recommended First)

**Priority**: HIGH - Ensure parameterization didn't break anything

1. **RV32I Regression Testing**
   ```bash
   # Run compliance tests to verify 40/42 still pass
   make compliance

   # Check for any new failures
   # Expected: 40/42 passing (fence_i and ma_data fail)
   ```

2. **Create RV64I Test Programs**
   - Simple RV64 test using LD/SD/LWU
   - Test XLEN-wide arithmetic
   - Verify sign-extension works correctly

3. **Validate Build System**
   - Try all 5 configuration targets
   - Verify each builds cleanly
   - Document any warnings or issues

**Estimated Time**: 2-3 hours

**Deliverables**:
- Regression test results
- RV64 test programs
- Validation report

### Option 2: M Extension Implementation

**Priority**: MEDIUM - Next major feature

1. **Design Phase**
   - Read RISC-V M extension spec
   - Design multiplier (iterative or Booth)
   - Design divider (restoring or non-restoring)
   - Plan pipeline integration

2. **Implementation**
   - Create `multiply_unit.v` module
   - Create `divide_unit.v` module
   - Integrate with pipeline (multi-cycle execution)
   - Add pipeline stalling for M instructions

3. **Testing**
   - Unit tests for multiply/divide
   - RV32M compliance tests
   - Edge cases (overflow, divide by zero)

**Estimated Time**: 1-2 weeks

**Deliverables**:
- Multiply and divide units
- Pipeline integration
- M extension compliance tests passing

### Option 3: Cache Implementation

**Priority**: MEDIUM - Performance enhancement

1. **I-Cache**
   - Direct-mapped design
   - Parameterized size
   - Miss handling

2. **D-Cache**
   - Set-associative design
   - Write-back or write-through
   - Cache coherency (if multicore)

3. **Integration**
   - Replace direct memory with cache
   - Add miss penalty
   - Performance measurement

**Estimated Time**: 2-3 weeks

**Deliverables**:
- I-cache and D-cache modules
- Cache controller
- Performance analysis report

### Option 4: RV64M Support

**Priority**: LOW - Depends on M extension

1. **64-bit Multiply/Divide**
   - MULW, DIVW, REMW, etc.
   - Sign-extension of 32-bit results

2. **Testing**
   - RV64M compliance tests
   - Edge cases

**Estimated Time**: 1 week (after M extension done)

---

## Files to Review Before Starting

### Critical Files
1. **PHASES.md** - Current status and roadmap
2. **ARCHITECTURE.md** - Design decisions and constraints
3. **docs/PARAMETERIZATION_GUIDE.md** - How parameterization works
4. **Makefile** - Build system targets
5. **rtl/config/rv_config.vh** - Configuration file

### Implementation Files
6. **rtl/core/rv_core_pipelined.v** - Top-level integration (715 lines)
7. **rtl/core/csr_file.v** - CSR implementation
8. **rtl/core/exception_unit.v** - Exception handling
9. **rtl/core/control.v** - Control signals with RV64 support

### Testing Infrastructure
10. **tb/integration/tb_core_pipelined.v** - Main testbench
11. **tools/run_compliance_pipelined.sh** - Compliance test script
12. **tests/riscv-tests/** - Official RISC-V test suite

---

## Common Workflows

### Workflow 1: Run Compliance Tests
```bash
cd /home/lei/rv1

# Make sure compliance tests are available
if [ -d "tests/riscv-tests" ]; then
  echo "Compliance tests ready"
else
  echo "Need to clone riscv-tests"
fi

# Run compliance suite
make compliance

# View results
cat sim/compliance_results.log
```

### Workflow 2: Create New Test Program
```bash
# 1. Create assembly file
cat > tests/asm/my_test.s << 'EOF'
.section .text
.globl _start

_start:
    # Your test code here
    addi x10, x0, 42

    # End with EBREAK
    ebreak
EOF

# 2. Assemble test
./tools/assemble.sh tests/asm/my_test.s

# 3. Run test
make run-test TEST=my_test

# 4. Check results
# Look for "Test PASSED" in output
```

### Workflow 3: Add New Module
```bash
# 1. Create module file
cat > rtl/core/new_module.v << 'EOF'
`include "config/rv_config.vh"

module new_module #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire [XLEN-1:0]  data_in,
  output wire [XLEN-1:0]  data_out
);

// Implementation here

endmodule
EOF

# 2. Create testbench
cat > tb/unit/tb_new_module.v << 'EOF'
`timescale 1ns/1ps

module tb_new_module;
  // Test implementation
endmodule
EOF

# 3. Update Makefile
# Add test target for new module

# 4. Test
make test-new-module
```

### Workflow 4: Debug with Waveforms
```bash
# 1. Run simulation (generates VCD)
make run-rv32i

# 2. Open waveform viewer
gtkwave sim/waves/core_pipelined.vcd &

# 3. Load signals of interest
# - Add: pc_out
# - Add: instr_out
# - Add: DUT.regfile.registers[10] (x10/a0 return value)
# - Add pipeline stage signals
```

---

## Known Issues & Limitations

### Expected Test Failures
1. **fence_i** - Expected failure (no instruction cache implemented)
2. **ma_data** - Timeout (needs investigation)

### RV64 Limitations
- No RV64 test programs created yet
- No RV64 compliance tests run yet
- RV64M extension not implemented

### Performance
- No caching (memory access is slow)
- No branch prediction (predict-not-taken only)
- Multiply/divide not implemented (would be multi-cycle)

### Extensions Not Implemented
- M: Multiply/divide
- A: Atomics
- C: Compressed instructions
- F/D: Floating point

---

## Testing Checklist

When you start the next session, verify:

- [ ] All files committed to git
- [ ] Working directory is `/home/lei/rv1`
- [ ] Can build RV32I: `make pipelined-rv32i`
- [ ] Can build RV64I: `make pipelined-rv64i`
- [ ] Can run tests: `make test-unit`
- [ ] Compliance tests ready: `ls tests/riscv-tests/`

---

## Git Status

Before starting next session, check:

```bash
cd /home/lei/rv1

# Check current branch
git branch

# Check for uncommitted changes
git status

# See recent commits
git log --oneline -10
```

**Expected**: Phase 5 changes committed, working directory clean

---

## Resource Links

### Documentation
- [RISC-V ISA Manual](https://riscv.org/technical/specifications/)
- [RV64I Spec](https://github.com/riscv/riscv-isa-manual/releases)
- [M Extension](https://github.com/riscv/riscv-isa-manual) (Chapter 7)
- [Compliance Tests](https://github.com/riscv/riscv-compliance)

### Project Docs
- `PHASES.md` - Development roadmap
- `ARCHITECTURE.md` - Design details
- `docs/PARAMETERIZATION_GUIDE.md` - Parameterization guide
- `SESSION_SUMMARY_2025-10-10_phase5_complete.md` - Latest session summary

### Tools
- Icarus Verilog: `man iverilog`
- RISC-V Toolchain: `riscv64-unknown-elf-gcc --version`
- GTKWave: `gtkwave --help`

---

## Quick Reference

### Configuration Defines
- `CONFIG_RV32I` - RV32I base ISA
- `CONFIG_RV32IM` - RV32I + M extension
- `CONFIG_RV32IMC` - RV32I + M + C extensions
- `CONFIG_RV64I` - RV64I base ISA
- `CONFIG_RV64GC` - RV64 full-featured

### Important Parameters
- `XLEN` - 32 or 64 (architecture width)
- `RESET_VECTOR` - Initial PC value
- `IMEM_SIZE` - Instruction memory size (default 16KB)
- `DMEM_SIZE` - Data memory size (default 16KB)

### Key Signals
- `pc_out` - Current program counter
- `instr_out` - Current instruction
- `DUT.regfile.registers[N]` - Register file contents
- `DUT.csr_file.mepc_r` - Exception PC
- `DUT.exception_unit.exception_valid` - Exception occurred

---

## Contact & Support

For questions or issues:
1. Check documentation in `docs/`
2. Review `PHASES.md` for roadmap
3. Look at session summaries for recent changes
4. Consult `ARCHITECTURE.md` for design decisions

---

## Summary

**You are here**: ✅ Phase 5 Complete - Fully parameterized processor

**Next logical steps**:
1. 🧪 Verify RV32I regression (recommended first)
2. 🧪 Test RV64I functionality
3. 🔧 Implement M extension
4. 🚀 Add caching for performance

**Build system ready**: 5 configurations available via Makefile

**Documentation complete**: Comprehensive guides and summaries created

**Ready to proceed**: All tools and infrastructure in place

---

*Good luck with the next session!* 🚀

---

**Last Updated**: 2025-10-10
**Phase**: 5 (Parameterization) - COMPLETE
**Next Phase**: Testing & Validation, then Extensions
